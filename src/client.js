var ws_liveserver_M3sp9 = new WebSocket("ws://" + location.host + location.pathname);
ws_liveserver_M3sp9.onmessage = function(msg) {
    if (msg.data === "update") {
        ws_liveserver_M3sp9.close();
        location.reload();
    };
};
