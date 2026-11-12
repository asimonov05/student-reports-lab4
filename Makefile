.PHONY: test report
test:
	bash tests/test.sh
report:
	./bin/student-report --help
