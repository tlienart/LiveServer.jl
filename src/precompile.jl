function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(servedocs_callback!),SimpleWatcher,String,String})   # time: 0.31880945
    isdefined(LiveServer, Symbol("#12#17")) && Base.precompile(Tuple{getfield(LiveServer, Symbol("#12#17")),HTTP.Streams.Stream{HTTP.Messages.Request, HTTP.ConnectionPool.Transaction{TCPSocket}}})   # time: 0.098543696
    Base.precompile(Tuple{typeof(get_fs_path),String})   # time: 0.087591365
    Base.precompile(Tuple{Core.kwftype(typeof(serve)),NamedTuple{(:port,), Tuple{Int64}},typeof(serve)})   # time: 0.07307711
    isdefined(LiveServer, Symbol("#11#16")) && Base.precompile(Tuple{getfield(LiveServer, Symbol("#11#16"))})   # time: 0.06859666
    isdefined(LiveServer, Symbol("#2#3")) && Base.precompile(Tuple{getfield(LiveServer, Symbol("#2#3"))})   # time: 0.030429186
    Base.precompile(Tuple{typeof(ws_tracker),HTTP.WebSockets.WebSocket,AbstractString})   # time: 0.03029817
    isdefined(LiveServer, Symbol("#6#7")) && Base.precompile(Tuple{getfield(LiveServer, Symbol("#6#7")),HTTP.WebSockets.WebSocket{IOBuffer}})   # time: 0.018438155
    Base.precompile(Tuple{typeof(watch_file!),SimpleWatcher,String})   # time: 0.0108271
    Base.precompile(Tuple{typeof(ws_upgrade),HTTP.Streams.Stream{HTTP.Messages.Request, IOBuffer}})   # time: 0.010094539
    Base.precompile(Tuple{typeof(set_callback!),SimpleWatcher,Function})   # time: 0.003649323
    Base.precompile(Tuple{typeof(append_slash),String})   # time: 0.003343235
    Base.precompile(Tuple{typeof(stop),SimpleWatcher})   # time: 0.002390376
    Base.precompile(Tuple{Type{SimpleWatcher}})   # time: 0.002108754
    Base.precompile(Tuple{typeof(start),SimpleWatcher})   # time: 0.001990792
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:sleeptime,), Tuple{Float64}},Type{SimpleWatcher},typeof(identity)})   # time: 0.00174082
    Base.precompile(Tuple{typeof(example)})   # time: 0.001634037
    Base.precompile(Tuple{typeof(has_changed),WatchedFile{String}})   # time: 0.001403002
    Base.precompile(Tuple{typeof(ws_tracker),HTTP.WebSockets.WebSocket{IOBuffer},String})   # time: 0.001390946
end
