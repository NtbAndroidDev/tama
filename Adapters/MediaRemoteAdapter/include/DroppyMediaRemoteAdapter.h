#pragma once

/// Entry point for `/usr/bin/perl`, installed as an XSUB (its perl arguments
/// are ignored). Streams Now Playing as one JSON object per line on stdout and
/// reads commands from stdin: play, pause, toggle, next, previous, seek <sec>,
/// refresh. Exits when stdin closes, i.e. when Tama quits.
void droppy_mediaremote_stream(void);
