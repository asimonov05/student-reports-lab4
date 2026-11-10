.PHONY: test gui report
test:
	bash tests/test.sh
	bash tests/gui-test.sh
gui:
	./bin/student-gui
report:
	./bin/student-report --help
