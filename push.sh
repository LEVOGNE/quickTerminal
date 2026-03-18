#!/bin/bash
# Push to both repos: quickTerminal (legacy) and SystemTrayTerminal (new)
# Run parallel until v1.6.0, then archive quickTerminal repo on GitHub.
set -e

echo "Pushing to quickTerminal (legacy)..."
git push origin main

echo "Pushing to SystemTrayTerminal (new)..."
git push stt main

echo "Done. Both repos updated."
