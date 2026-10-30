#include <ArduinoJson.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  DynamicJsonDocument doc(4096);
  DeserializationError error = deserializeJson(doc, data, size);
  if (error)
    return -1;
  std::string json;
  serializeJson(doc, json);
  return 0;
}
