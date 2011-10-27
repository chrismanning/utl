#!/bin/sh

dmd utl/*.d -oflibutl -lib -gc -unittest -inline;
dmd test/test.d-Llibutl.a -gc -unittest -inline;

dmd unittests.d utl/*.d -unittest -inline;
${PWD}/unittests;
