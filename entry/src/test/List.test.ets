import sseParserTest from './SseParser.test';
import apiUnwrapTest from './ApiUnwrap.test';
import webAlignTest from './WebAlign.test';
import safeUrlTest from './SafeUrl.test';
import inboxFeedTest from './InboxFeed.test';
import convProtocolTest from './ConvProtocol.test';

export default function testsuite() {
  sseParserTest();
  apiUnwrapTest();
  webAlignTest();
  safeUrlTest();
  inboxFeedTest();
  convProtocolTest();
}
