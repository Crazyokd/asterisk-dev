#!/bin/env bash

wscat -c "ws://localhost:8088/ari/events?api_key=asterisk:passwd&app=test"
