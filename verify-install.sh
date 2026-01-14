#!/usr/bin/env bash
# Verify statusline installation

SYMLINK_PATH="$HOME/.claude/statusline.sh"
TARGET_PATH="$HOME/.claude/claude-code-statusline/statusline.sh"

if [ -L "$SYMLINK_PATH" ]; then
    CURRENT_TARGET=$(readlink -f "$SYMLINK_PATH")
    EXPECTED_TARGET=$(readlink -f "$TARGET_PATH")

    if [ "$CURRENT_TARGET" = "$EXPECTED_TARGET" ]; then
        echo "✓ Symlink is correctly configured"
        exit 0
    else
        echo "✗ Symlink points to wrong target: $CURRENT_TARGET"
        echo "  Expected: $EXPECTED_TARGET"
        exit 1
    fi
elif [ -f "$SYMLINK_PATH" ]; then
    echo "✗ $SYMLINK_PATH is a regular file, not a symlink!"
    echo "  Run: rm ~/.claude/statusline.sh && ln -s $TARGET_PATH ~/.claude/statusline.sh"
    exit 1
else
    echo "✗ Symlink does not exist"
    echo "  Run: ln -s $TARGET_PATH ~/.claude/statusline.sh"
    exit 1
fi
