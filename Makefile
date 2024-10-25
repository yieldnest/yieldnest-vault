

account :; cast wallet import $(ACCOUNT_NAME) --interactive

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)
cover		:;	forge coverage --watch --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage
show		:;	npx http-server ./coverage