// Pure policy; values are Quickshell's visual volumes (1 == 100%).
function clamp(value) { return Math.max(0, Math.min(1, value)); }

function identity(properties, runtimeKey) {
    if (properties["application.id"]) return "app:" + properties["application.id"];
    if (properties["client.id"] !== undefined && properties["client.id"] !== "")
        return "client:" + properties["client.id"];
    return "node:" + runtimeKey;
}

function maximum(values) { return values.length ? Math.max.apply(null, values) : 0; }

function scaled(values, target, remembered) {
    target = clamp(target);
    const max = maximum(values);
    const ratios = max > 0 ? values.map(value => value / max) : remembered;
    return {
        values: ratios && ratios.length === values.length
            ? ratios.map(ratio => ratio * target) : values.map(() => target),
        ratios: ratios
    };
}

function muteState(values) {
    if (values.length && values.every(value => value)) return "muted";
    return values.some(value => value) ? "mixed" : "audible";
}
