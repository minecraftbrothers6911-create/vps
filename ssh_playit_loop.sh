#!/bin/bash
set -e

echo "------------------------------"
echo "Git Setup"
echo "------------------------------"
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links
git fetch origin main
git reset --hard origin/main

echo "------------------------------"
echo "Ensure Playit agent exists"
echo "------------------------------"
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
  wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
  chmod +x "$AGENT_BIN"
fi

echo "------------------------------"
echo "Restore Playit config if exists"
echo "------------------------------"
mkdir -p ~/.config/playit_gg
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit_gg/playit.toml || echo "[Playit] No saved config yet"

echo "------------------------------"
echo "Restore previous claim link"
echo "------------------------------"
if [ ! -f links/playit_claim.txt ]; then
  aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
fi

echo "------------------------------"
echo "Start Playit agent"
echo "------------------------------"
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN > playit.log 2>&1 &
sleep 15

echo "------------------------------"
echo "Background loop: Refresh tmate SSH every 15 minutes"
echo "------------------------------"
(
while true; do
  pkill tmate || true
  rm -f /tmp/tmate.sock
  tmate -S /tmp/tmate.sock new-session -d
  tmate -S /tmp/tmate.sock wait tmate-ready 30 || true

  TMATE_SSH=""
  while [ -z "$TMATE_SSH" ]; do
    sleep 2
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' || true)
  done

  echo "$TMATE_SSH" > links/ssh.txt
  echo "[INFO] Refreshed SSH: $TMATE_SSH"

  git fetch origin main
  git reset --hard origin/main
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  sleep 900  # 15 minutes
done
) &

echo "------------------------------"
echo "Full server backup every 30 minutes"
echo "------------------------------"
(
while true; do
  echo "[Backup] Starting full server backup at $(date -u)"

  if [ -d server ]; then
    cd server
    rm -f ../mcbackup.zip   # remove old backup
    zip -r ../mcbackup.zip . >/dev/null
    cd ..

    echo "[Backup] Uploading to Filebase..."
    n=0
    until [ $n -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
      sleep 30
      n=$((n+1))
    done
    echo "[Backup] Full server backup done ✅"
  else
    echo "[Backup] No server directory found, skipping"
  fi

  echo "[INFO] Sleeping 30 minutes..."
  sleep 1800  # 30 minutes
done
) &

echo "------------------------------"
echo "Minecraft server screen check"
echo "------------------------------"
# Check if server is running; if not, start it in screen
if ! pgrep -f "java.*paper.jar" >/dev/null; then
  echo "[INFO] Starting Minecraft server in screen..."
  screen -dmS mc java -Xmx12G -Xms2G -jar paper.jar nogui
fi

echo "[INFO] Script setup complete. Playit + 30min backup + tmate loop running in background."

# Keep script running so Actions doesn't exit
tail -f /dev/null
