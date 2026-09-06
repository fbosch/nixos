declare module "node:os" {
  export function hostname(): string;
}

declare module "@earendil-works/pi-coding-agent" {
  interface ExtensionAPI {
    exec(
      command: string,
      args: readonly string[],
      options?: { readonly timeout?: number },
    ): Promise<{
      readonly code: number;
      readonly killed: boolean;
      readonly stderr: string;
      readonly stdout: string;
    }>;

    on(
      event: "session_start",
      handler: (
        event: { readonly reason: string },
        context: ExtensionContext,
      ) => void | Promise<void>,
    ): void;

    on(
      event: "before_agent_start",
      handler: (
        event: BeforeAgentStartEvent,
      ) => BeforeAgentStartResult | Promise<BeforeAgentStartResult>,
    ): void;
  }

  interface ExtensionContext {
    readonly cwd: string;
    readonly hasUI: boolean;
    readonly ui: {
      notify(message: string, level: "error" | "info" | "warning"): void;
    };
  }

  interface BeforeAgentStartEvent {
    readonly systemPrompt: string;
  }

  interface BeforeAgentStartResult {
    readonly systemPrompt: string;
  }
}
