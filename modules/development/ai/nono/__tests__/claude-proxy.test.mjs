import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { credentialDefinitions } from "../scripts/credentials/definitions.mts";

const secret = "synthetic-claude-access-token";
const refresh = "synthetic-claude-refresh-token";
const helper = fileURLToPath(new URL("../scripts/credentials/claude-credential.mts", import.meta.url));

function reply(response, streaming) {
  const message = {id:"msg_fixture",type:"message",role:"assistant",model:"claude-sonnet-4-6",content:[{type:"text",text:"fixture completion"}],stop_reason:"end_turn",stop_sequence:null,usage:{input_tokens:1,output_tokens:1}};
  if (!streaming) {
    response.writeHead(200,{"content-type":"application/json"});
    response.end(JSON.stringify(message));
    return;
  }
  response.writeHead(200,{"content-type":"text/event-stream"});
  for (const event of [
    {type:"message_start",message:{...message,content:[],stop_reason:null,usage:{input_tokens:1,output_tokens:0}}},
    {type:"content_block_start",index:0,content_block:{type:"text",text:""}},
    {type:"content_block_delta",index:0,delta:{type:"text_delta",text:"fixture completion"}},
    {type:"content_block_stop",index:0},
    {type:"message_delta",delta:{stop_reason:"end_turn",stop_sequence:null},usage:{output_tokens:1}},
    {type:"message_stop"},
  ]) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  response.end();
}

test("real Claude CLI uses the proxy placeholder while only the host upstream receives the captured token", {
  skip: process.platform !== "linux" || !process.env.NONO_PROXY_TEST_BINARY || !process.env.CLAUDE_TEST_BINARY,
  timeout: 60000,
}, async () => {
  const root=realpathSync(mkdtempSync(join(process.cwd(),".pi-claude-proxy-")));
  const home=join(root,"home"), work=join(root,"work"), temporary=join(root,"tmp");
  const credential=join(home,".claude",".credentials.json");
  for(const path of [home,work,temporary,join(home,".claude"),join(home,".claude","projects")]) mkdirSync(path,{recursive:true,mode:0o700});
  writeFileSync(credential,JSON.stringify({claudeAiOauth:{accessToken:secret,refreshToken:refresh,expiresAt:Date.now()+3_600_000,scopes:["user:inference"]}}),{mode:0o600});
  const requests=[];
  const failures=[];
  let unrelatedRequests = 0;
  const unrelated = createServer((request, response) => { unrelatedRequests++; response.end("unrelated"); });
  const upstream=createServer((request,response)=>{
    const parts=[];
    request.on("data",chunk=>parts.push(chunk));
    request.on("end",()=>{
      try {
        assert.equal(request.headers.authorization,`Bearer ${secret}`);
        assert.ok(!JSON.stringify(request.headers).includes(refresh));
        requests.push({method:request.method,path:request.url});
        if (request.url === "/redirect") {
          response.writeHead(302, {location:`http://127.0.0.1:${unrelated.address().port}/unrelated`});
          response.end();
          return;
        }
        const body=JSON.parse(Buffer.concat(parts).toString()||"{}");
        if(request.url.startsWith("/v1/messages/count_tokens")) {
          response.writeHead(200,{"content-type":"application/json"});response.end('{"input_tokens":1}');
        } else if(request.url.startsWith("/v1/messages")) reply(response,body.stream);
        else { response.writeHead(404,{"content-type":"application/json"});response.end('{"error":{"type":"not_found_error","message":"local fixture"}}'); }
      } catch(error) { failures.push(error);response.writeHead(500);response.end("fixture failure"); }
    });
  });
  try {
    unrelated.listen(0,"127.0.0.1");await once(unrelated,"listening");
    upstream.listen(0,"127.0.0.1");await once(upstream,"listening");
    const profile=join(root,"profile.json");
    writeFileSync(profile,JSON.stringify({
      extends:"default",filesystem:{read:["/nix/store"],allow:[work,temporary,join(home,".claude","projects")],deny:[credential]},
      linux:{af_unix_mediation:"pathname",sandbox_policy:"landlock"},
      network:{credentials:["anthropic"],custom_credentials:{anthropic:{...credentialDefinitions.anthropic.route,upstream:`http://127.0.0.1:${upstream.address().port}`,credential_key:"cmd://anthropic"}}},
      credential_capture:{anthropic:{...credentialDefinitions.anthropic.capture,command:[process.execPath,helper]}},
    }));
    const probe=`
      const assert=require("node:assert/strict"),fs=require("node:fs"),{spawnSync}=require("node:child_process");
      assert.throws(()=>fs.readFileSync(${JSON.stringify(credential)}),e=>["EACCES","EPERM"].includes(e.code));
      assert.ok(process.env.CLAUDE_CODE_OAUTH_TOKEN);
      assert.notEqual(process.env.CLAUDE_CODE_OAUTH_TOKEN,${JSON.stringify(secret)});
      assert.ok(!JSON.stringify(process.env).includes(${JSON.stringify(refresh)}));
      const captured = spawnSync(process.execPath, [${JSON.stringify(helper)}], {env:process.env,encoding:"utf8",timeout:3000});
      assert.equal(captured.status,1,"the capture helper cannot recover the credential from inside confinement");
      assert.equal(captured.stdout,"");
      const result=spawnSync(${JSON.stringify(process.env.CLAUDE_TEST_BINARY)},[
        "--print","--output-format","json","--model","claude-sonnet-4-6",
        "--tools","","--strict-mcp-config","--mcp-config",'{"mcpServers":{}}',
        "--setting-sources","","--safe-mode","--no-session-persistence","--permission-mode","dontAsk","local fixture",
      ],{encoding:"utf8",timeout:25000,env:{...process.env,CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1"}});
      assert.ifError(result.error);
      assert.equal(result.status,0,result.stdout+result.stderr);
      assert.match(result.stdout,/fixture completion/);
      assert.ok(!result.stdout.includes(${JSON.stringify(secret)}));
      (async () => {
        const denied = await fetch(process.env.ANTHROPIC_BASE_URL + "/v1/messages", {
          method:"POST", headers:{Authorization:"Bearer wrong-placeholder","content-type":"application/json"}, body:"{}", signal:AbortSignal.timeout(3000),
        });
        assert.ok([401,403].includes(denied.status), "invalid proxy credential must be rejected");
        const redirected = await fetch(process.env.ANTHROPIC_BASE_URL + "/redirect", {
          headers:{Authorization:"Bearer " + process.env.CLAUDE_CODE_OAUTH_TOKEN}, redirect:"manual", signal:AbortSignal.timeout(3000),
        });
        assert.equal(redirected.status,302,"the proxy must not forward captured credentials across a redirect");
        console.log("Claude CLI completed using isolated proxy credentials");
      })().catch(error=>{console.error(error);process.exitCode=1;});
    `;
    const command=[process.env.NONO_PROXY_TEST_BINARY,"run","--profile",profile,"--allow-cwd","--no-audit","--no-rollback","--",process.execPath,"-e",probe];
    const runner=`
      import { credentialProxySession } from ${JSON.stringify(new URL("../scripts/credentials/proxy.mts",import.meta.url).href)}; import * as Effect from ${JSON.stringify(import.meta.resolve("effect/Effect"))};
      import assert from "node:assert/strict";
      import {rmSync,writeFileSync} from "node:fs";
      rmSync(${JSON.stringify(credential)});
      const idle = [...${JSON.stringify(command)}];
      idle[idle.length-1] = "console.log('other providers may start without a Claude login')";
      const idleResult = await Effect.runPromise(credentialProxySession(${JSON.stringify(process.env.NONO_PROXY_TEST_BINARY)},${JSON.stringify(profile)},idle,process.env,{sandboxed:true}));
      assert.equal(idleResult.status,0);
      writeFileSync(${JSON.stringify(credential)},JSON.stringify({claudeAiOauth:{accessToken:${JSON.stringify(secret)},refreshToken:${JSON.stringify(refresh)},expiresAt:Date.now()+3600000,scopes:["user:inference"]}}),{mode:0o600});
      const result=await Effect.runPromise(credentialProxySession(${JSON.stringify(process.env.NONO_PROXY_TEST_BINARY)},${JSON.stringify(profile)},${JSON.stringify(command)},process.env,{sandboxed:true}));
      if(result.error)throw result.error;process.exit(result.status??1);
    `;
    const child=spawn(process.execPath,["--input-type=module","-e",runner],{
      cwd:work,env:{HOME:home,PATH:process.env.PATH,TMPDIR:temporary,NO_COLOR:"1"},stdio:["ignore","pipe","pipe"],
    });
    let output="";
    child.stdout.on("data",chunk=>output+=chunk);
    child.stderr.on("data",chunk=>output+=chunk);
    const [status,signal]=await once(child,"exit");
    assert.equal(signal,null,output);
    assert.equal(status,0,output);
    assert.equal(failures.length,0,failures[0]?.message);
    assert.ok(requests.some(request=>request.method==="POST"&&request.path.startsWith("/v1/messages")),JSON.stringify(requests));
    assert.equal(unrelatedRequests,0,"redirect targets must not receive host credentials");
    assert.ok(!output.includes(secret));
    assert.ok(!output.includes(refresh));
  } finally {
    unrelated.closeAllConnections();
    await new Promise(resolve=>unrelated.close(resolve));
    upstream.closeAllConnections();
    await new Promise(resolve=>upstream.close(resolve));
    rmSync(root,{recursive:true,force:true});
  }
});
