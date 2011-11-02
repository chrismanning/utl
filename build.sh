#!/bin/sh

dmd utl/*.d -oflibutl -lib -gc -inline;
dmd test/test.d -Llibutl.a -gc -inline -oftest1;

dmd unittests.d utl/*.d -unittest -gc -debug -inline && ${PWD}/unittests;
