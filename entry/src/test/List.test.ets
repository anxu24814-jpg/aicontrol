import localUnitTest from './LocalUnit.test';
import streamingDocumentTest from './StreamingDocument.test';
import chatFollowMotionTest from './ChatFollowMotion.test';

export default function testsuite() {
  localUnitTest();
  streamingDocumentTest();
  chatFollowMotionTest();
}