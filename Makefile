.PHONY: test gui report
test:
	bash tests/test.sh
	bash tests/gui-test.sh
gui:
	./student-gui
report:
	./student-report --help
