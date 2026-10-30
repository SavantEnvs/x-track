// Known-answer probe: reads a GPX document on stdin, prints every parsed track point.
#include "gpx_support.h"
#include <stdio.h>
#include <string>

int main() {
  std::string in;
  char buf[4096];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), stdin)) > 0)
    in.append(buf, n);

  Feed feed = {reinterpret_cast<const uint8_t *>(in.data()), in.size(), 0};
  GPX_Parser parser;
  parser.userData = &feed;
  parser.SetCallback(feedAvailable, feedRead);

  GPX_Parser::Point_t p = {};
  for (;;) {
    int flag = parser.ReadNext(&p);
    if (flag & GPX_Parser::PARSER_FLAG_EOF)
      break;
    printf("flag=%d lat=%.4f lon=%.4f ele=%.2f time=%04d-%02d-%02dT%02d:%02d:%02d\n", flag,
           p.latitude, p.longitude, p.altitude, p.time.year, p.time.month, p.time.day,
           p.time.hour, p.time.minute, p.time.second);
  }
  return 0;
}
