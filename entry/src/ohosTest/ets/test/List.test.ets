import sseParserTest from '../../../test/SseParser.test';
import safeUrlTest from '../../../test/SafeUrl.test';
import inboxFeedTest from '../../../test/InboxFeed.test';

export default function testsuite() {
  sseParserTest();
  safeUrlTest();
  inboxFeedTest();
}
