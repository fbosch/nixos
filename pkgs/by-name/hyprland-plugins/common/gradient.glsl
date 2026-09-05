const float GRADIENT_QUARTER_TURN = 1.57079632679489661923;
const float GRADIENT_HALF_TURN = 3.14159265358979323846;
const float GRADIENT_THREE_QUARTER_TURN = 4.71238898038468985769;
const float GRADIENT_FULL_TURN = 6.28318530717958647692;

float gradientProgress(float x, float y, float angle, int gradientLength) {
    float finalAngle;
    if (angle > GRADIENT_THREE_QUARTER_TURN) {
        y = 1.0 - y;
        finalAngle = GRADIENT_FULL_TURN - angle;
    } else if (angle > GRADIENT_HALF_TURN) {
        x = 1.0 - x;
        y = 1.0 - y;
        finalAngle = angle - GRADIENT_HALF_TURN;
    } else if (angle > GRADIENT_QUARTER_TURN) {
        x = 1.0 - x;
        finalAngle = GRADIENT_HALF_TURN - angle;
    } else {
        finalAngle = angle;
    }

    float sine = sin(finalAngle);
    float progress = (y * sine + x * (1.0 - sine)) * float(gradientLength - 1);
    return clamp(progress, float(0.0), float(gradientLength - 1));
}
