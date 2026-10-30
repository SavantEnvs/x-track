// Known-answer probe: reads JSON on stdin, prints canonical JSON and MessagePack hex.
#include <ArduinoJson.h>
#include <cstdio>
#include <iostream>
#include <iterator>
#include <string>

int main() {
  std::string in((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  DynamicJsonDocument doc(4096);
  if (deserializeJson(doc, in)) {
    std::puts("ERROR");
    return 1;
  }
  std::string json, mp;
  serializeJson(doc, json);
  serializeMsgPack(doc, mp);
  std::printf("%s\n", json.c_str());
  for (size_t i = 0; i < mp.size(); i++)
    std::printf("%02x", (unsigned)(unsigned char)mp[i]);
  std::printf("\n");
  return 0;
}
