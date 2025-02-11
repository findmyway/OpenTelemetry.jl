export TracerProvider

using Base.Threads
using Dates: time

struct Tracer{
    S<:AbstractSampler,
    SP<:AbstractSpanProcessor,
    G<:AbstractIdGenerator
} <: API.AbstractTracer
    sampler::S
    resource::Resource
    span_processor::SP
    id_generator::G
    instrumentation::InstrumentationInfo
end

function API.create_span(
    name::String,
    t::Tracer;
    parent_context=current_context(),
    kind=SPAN_KIND_INTERNAL,
    attributes=Attributes(;is_mutable=true),
    links=[],
    start_time=time()
)
    parent_span_ctx = parent_context |> current_span |> span_context
    if parent_span_ctx === INVALID_SPAN_CONTEXT
        trace_id = generate_trace_id(t.id_generator)
    else
        trace_id = parent_span_ctx.trace_id
    end

    sampling_result = should_sample(
        t.sampler,
        parent_context,
        trace_id,
        name,
        kind,
        attributes,
        links,
        parent_span_ctx.trace_state
    )

    span_ctx = SpanContext(
        trace_id = trace_id,
        span_id = generate_span_id(t.id_generator),
        is_remote=false,
        trace_flag = TraceFlag(sampled=is_sampled(sampling_result)),
        trace_state=sampling_result.trace_state
    )

    if is_recording(sampling_result)
        Span(
            ;name=name,
            span_context=span_ctx,
            parent_context=parent_context,
            kind=kind,
            attributes=attributes,
            links=links,
            start_time=start_time
        )
    else
        NonRecordingSpan(span_ctx)
    end
end

#####
# TracerProvider
#####

Base.@kwdef struct TracerProvider{
    S<:AbstractSampler,
    IDG<:AbstractIdGenerator
} <: API.AbstractTracerProvider
    sampler::S=DEFAULT_ON
    resource::Resource=Resource()
    span_processor::MultiSpanProcessor=MultiSpanProcessor()
    id_generator::IDG=RandomIdGenerator()
end

shut_down!(p::TracerProvider) = shut_down!(p.span_processor)

force_flush!(p::TracerProvider, args...) = force_flush!(p.span_processor, args...)

function API.get_tracer(p::TracerProvider, instrumentation_name, instrumentation_version=nothing)
    Tracer(
        p.sampler,
        p.resource,
        p.span_processor,
        p.id_generator,
        isnothing(instrumentation_version) ? InstrumentationInfo(instrumentation_name) : InstrumentationInfo(instrumentation_name, instrumentation_version)
    )
end
