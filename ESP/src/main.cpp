#include <Arduino.h>
#include <Wire.h>

/* ===================== BLE INCLUDES ===================== */
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

/* ===================== PIN DEFINITIONS ===================== */
#define IR_PIN 27
#define BUZZER_PIN 4
#define VIBRO_PIN 2
#define SDA_PIN 21
#define SCL_PIN 22

/* ===================== DYNAMIC WEIGHTS & SCORES ===================== */
float wBlink = 0.33, wTilt = 0.33, wSpeed = 0.34;
float blinkScore = 0, tiltScore = 0, speedScore = 0;
float totalRiskScore = 0;
uint32_t lastIRChange = 0;
bool irReliable = true;

/* ===================== PARAMETERS ===================== */
#define DEBOUNCE_MS 50
#define LONG_BLINK_MS 400
#define MAX_TILT_DEG 45.0f
#define MAX_SPEED_DPS 200.0f

/* ===================== MPU6050 DEFINITIONS ===================== */
#define MPU_ADDR 0x68
#define REG_PWR_MGMT_1   0x6B
#define REG_ACCEL_XOUT_H 0x3B
#define REG_GYRO_CONFIG  0x1B
#define REG_ACCEL_CONFIG 0x1C
#define ACCEL_FS_SEL 1
#define GYRO_FS_SEL  1

float accelLSB = 8192.0f;
float gyroLSB  = 65.5f;
float gbx = 0, gby = 0;
uint32_t lastMicros = 0;

/* ===================== ACCIDENT FLAGS ===================== */
bool accidentDetected = false;
bool accidentSent = false;

/* ===================== BLE DEFINITIONS ===================== */
#define BLE_SERVICE_UUID  "12345678-1234-1234-1234-1234567890ab"
#define BLE_DATA_UUID     "abcd1234-1234-1234-1234-1234567890ab"

BLECharacteristic *bleDataCharacteristic;
bool bleDeviceConnected = false;

/* ===================== COMPLEMENTARY FILTER ===================== */
class ComplementaryFilter {
public:
  explicit ComplementaryFilter(float alpha = 0.98f)
    : alpha_(alpha), roll_(0), pitch_(0), initialized_(false) {}

  void update(float ax, float ay, float az,
              float gx, float gy, float dt) {

    float rollAcc  = atan2f(ay, az);
    float pitchAcc = atan2f(-ax, sqrtf(ay*ay + az*az));

    if (!initialized_) {
      roll_ = rollAcc;
      pitch_ = pitchAcc;
      initialized_ = true;
      return;
    }

    roll_  += gx * dt;
    pitch_ += gy * dt;

    float amag = sqrtf(ax*ax + ay*ay + az*az);
    bool accelOK = (amag > 0.85f && amag < 1.15f);

    float a = accelOK ? alpha_ : 1.0f;
    roll_  = a * roll_  + (1 - a) * rollAcc;
    pitch_ = a * pitch_ + (1 - a) * pitchAcc;
  }

  float rollDeg()  const { return roll_  * RAD_TO_DEG; }
  float pitchDeg() const { return pitch_ * RAD_TO_DEG; }

private:
  float alpha_, roll_, pitch_;
  bool initialized_;
};

ComplementaryFilter filter(0.98f);

/* ===================== I2C HELPERS ===================== */
void i2cWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

void i2cRead(uint8_t reg, uint8_t *buf, uint8_t len) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, len);
  for (uint8_t i = 0; i < len && Wire.available(); i++)
    buf[i] = Wire.read();
}

int16_t be16(uint8_t *b) {
  return (b[0] << 8) | b[1];
}

/* ===================== GYRO CALIBRATION ===================== */
void calibrateGyro(int samples = 600) {
  long sx = 0, sy = 0;
  uint8_t b[14];

  for (int i = 0; i < samples; i++) {
    i2cRead(REG_ACCEL_XOUT_H, b, 14);
    sx += be16(&b[8]);
    sy += be16(&b[10]);
    delay(2);
  }

  gbx = (sx / (float)samples) / gyroLSB * DEG_TO_RAD;
  gby = (sy / (float)samples) / gyroLSB * DEG_TO_RAD;
}

/* ===================== SENSOR HEALTH & WEIGHTING ===================== */
void updateWeights() {
  if (millis() - lastIRChange > 10000) {
    irReliable = false;
    wBlink = 0.10;
    wTilt = 0.45;
    wSpeed = 0.45;
  } else {
    irReliable = true;
    wBlink = 0.40;
    wTilt = 0.30;
    wSpeed = 0.30;
  }
}

/* ===================== BLE CALLBACK ===================== */
class BLEServerCallbacksImpl : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    bleDeviceConnected = true;
  }
  void onDisconnect(BLEServer* pServer) {
    bleDeviceConnected = false;
  }
};

/* ===================== SETUP ===================== */
void setup() {

  Serial.begin(115200);
  delay(200);

  pinMode(IR_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(VIBRO_PIN, OUTPUT);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(400000);

  i2cWrite(REG_PWR_MGMT_1, 0x00);
  i2cWrite(REG_ACCEL_CONFIG, ACCEL_FS_SEL << 3);
  i2cWrite(REG_GYRO_CONFIG,  GYRO_FS_SEL  << 3);

  Serial.println("Calibrating gyro...");
  calibrateGyro();
  Serial.println("System ready.");

  lastMicros = micros();

  /* ===================== BLE INIT ===================== */
  BLEDevice::init("ESP32_ACCIDENT_MONITOR");

  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLEServerCallbacksImpl());

  BLEService *pService = pServer->createService(BLE_SERVICE_UUID);

  bleDataCharacteristic = pService->createCharacteristic(
                            BLE_DATA_UUID,
                            BLECharacteristic::PROPERTY_NOTIFY
                          );
  bleDataCharacteristic->addDescriptor(new BLE2902());

  pService->start();
  BLEDevice::startAdvertising();

  Serial.println("BLE Ready.");
}

/* ===================== LOOP ===================== */
void loop() {

  uint32_t now = micros();
  float dt = (now - lastMicros) * 1e-6f;
  lastMicros = now;

  uint8_t b[14];
  i2cRead(REG_ACCEL_XOUT_H, b, 14);

  float ax = be16(&b[0]) / accelLSB;
  float ay = be16(&b[2]) / accelLSB;
  float az = be16(&b[4]) / accelLSB;
  float gy = be16(&b[10]) / gyroLSB * DEG_TO_RAD - gby;

  filter.update(ax, ay, az, 0, gy, dt);

  float pitch = filter.pitchDeg();
  float gy_dps = abs(gy * RAD_TO_DEG);

  tiltScore = constrain((pitch / MAX_TILT_DEG) * 100, 0, 100);
  speedScore = constrain((gy_dps / MAX_SPEED_DPS) * 100, 0, 100);

  bool currentIR = digitalRead(IR_PIN);
  static uint32_t eyeCloseStart = 0;
  static bool prevIR = HIGH;

  if (currentIR != prevIR) lastIRChange = millis();

  if (currentIR == LOW) {
    uint32_t duration = millis() - eyeCloseStart;
    blinkScore = constrain((duration / (float)LONG_BLINK_MS) * 100, 0, 100);
  } else {
    blinkScore = 0;
    eyeCloseStart = millis();
  }
  prevIR = currentIR;

  updateWeights();

  totalRiskScore = (wBlink * blinkScore) +
                   (wTilt * tiltScore) +
                   (wSpeed * speedScore);

  /* ===================== ACCIDENT DETECTION ===================== */
  if (tiltScore > 85 || speedScore > 90 || totalRiskScore > 85) {
    accidentDetected = true;
  }

  /* ===================== ALERT CONTROL ===================== */
  String alert = "NORMAL";

  if (totalRiskScore > 75) {
    digitalWrite(BUZZER_PIN, HIGH);
    digitalWrite(VIBRO_PIN, HIGH);
    alert = "DANGER";
  }
  else if (totalRiskScore > 40) {
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(VIBRO_PIN, HIGH);
    alert = "WARNING";
  }
  else {
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(VIBRO_PIN, LOW);
  }

  Serial.print("Score: ");
  Serial.print(totalRiskScore);
  Serial.println(" | Alert: " + alert);

  /* ===================== BLE ACCIDENT TRANSMIT ===================== */
  if (bleDeviceConnected && accidentDetected && !accidentSent) {

    String jsonData = "{";
    jsonData += "\"accident\":\"YES\",";

    if (totalRiskScore > 95) {
      jsonData += "\"severity\":\"CRITICAL\",";
      jsonData += "\"message\":\"Severe crash detected. Immediate medical attention required.\"";
    }
    else if (totalRiskScore > 85) {
      jsonData += "\"severity\":\"HIGH\",";
      jsonData += "\"message\":\"High impact detected. Please check rider immediately.\"";
    }
    else {
      jsonData += "\"severity\":\"MODERATE\",";
      jsonData += "\"message\":\"Sudden fall detected. Ensure rider safety.\"";
    }

    jsonData += "}";

    bleDataCharacteristic->setValue(jsonData.c_str());
    bleDataCharacteristic->notify();

    accidentSent = true;
  }

  delay(20);
}