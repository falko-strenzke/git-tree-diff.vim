#!/bin/bash
echo "$@" >> "${GTD_TEST_DIR:?GTD_TEST_DIR not set - run the tests via run.sh}/browse.log"
