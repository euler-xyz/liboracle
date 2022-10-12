.PHONY: test

test:
	forge test
	forge test -vv --match-contract RingBufferTest --match-test test_read | node test/processRingBufferTest.js
