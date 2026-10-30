// Fuzzes X-Track's GPX_Parser (the track-replay GPX reader) over an in-memory byte stream.
#include "gpx_support.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  Feed feed = {data, size, 0};
  GPX_Parser parser;
  parser.userData = &feed;
  parser.SetCallback(feedAvailable, feedRead);

  GPX_Parser::Point_t point = {};
  for (unsigned i = 0; i < 1024; i++) {
    int flag = parser.ReadNext(&point);
    if (flag & GPX_Parser::PARSER_FLAG_EOF)
      break;
  }
  return 0;
}
