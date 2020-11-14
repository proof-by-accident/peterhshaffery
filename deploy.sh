#!/bin/bash
USER=petershaffery
HOST=claudette.mayfirst.org
DIR=web

hugo && rsync -avz --delete public/* ${USER}@${HOST}:~/${DIR}
hugo && rsync -avz --delete static/* ${USER}@${HOST}:~/${DIR}

exit 0
