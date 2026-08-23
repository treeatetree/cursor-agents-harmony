import sseParserTest from '../../../test/SseParser.test';
import safeUrlTest from '../../../test/SafeUrl.test';
import inboxFeedTest from '../../../test/InboxFeed.test';
import convProtocolTest from '../../../test/ConvProtocol.test';

/**
 * WebAlign.test / ApiUnwrap.test live in src/test/List.test.ets but fail ohosTest
 * ArkTS (untyped object literals). Keep this runner on the suites that compile.
 */
export default function testsuite() {
  sseParserTest();
  safeUrlTest();
  inboxFeedTest();
  convProtocolTest();
}
