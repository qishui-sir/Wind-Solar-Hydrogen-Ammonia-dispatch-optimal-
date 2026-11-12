function [lower, info] = O1EtaCertificate(cfg, cap_usd, source_dir, hash_fn)
%O1ETACERTIFICATE 11_9 eta certificate: load, validate, or recompute.
%
%   This ports the lower-bound evidence produced in test/11_9 into the main
%   O1 path.  The certificate is a valid lower bound for the ORIGINAL
%   delta=0.5 USD/t problem:
%
%       base  : eta=0.03 on the annual production equality row, adaptive
%               48/96/192 partition, local z-only integer MILPs;
%       cut   : the base certificate proves N(x) >= K for integer x, so
%               sum(z) >= K is a valid cut; the cut-row dual mu=1 and the
%               local q=0 give N(x) >= K - guard.
%
%   The stored cache (src/cache/O1_eta_certificate_cache.mat) is the fast
%   path used by main.  If it is missing, or if economic_eta_recompute is
%   true, the function recomputes the base certificate from the frozen
%   partition context/certificate and saves the cache.  The level files
%   O1_eta_level48/96/192.mat are reused when present.
%
%   Inputs
%     cfg        O1 configuration struct (cache_directory, use_cache, ...)
%     cap_usd    current loose cost cap (fail); the certificate is valid
%                when cap_usd <= the certificate's source cap.
%     source_dir optional partition context directory for recomputation.
%     hash_fn    optional handle to O1Economics' partition21_hash.
%
%   Outputs
%     lower      integer lower bound (416 for the stored certificate), or
%                -Inf when the cache is missing/invalid.
%     info       validation/provenance record.
%
%   The function never modifies the primal model, the cost cap, the main
%   cache, or any src/ file.  Failures are reported by info.reason and do
%   not abort main.

lower = -Inf;
info = struct('validated', false, 'reason', '', ...
    'source_context_signature', "", 'source_model_signature', "", ...
    'source_cap_usd', NaN, 'source_cap_row', NaN, 'eta', NaN, ...
    'cert', NaN, 'base_cert', NaN, 'cut_k', NaN, 'K_lower', NaN, ...
    'method', "", 'source', "");

if nargin < 4, hash_fn = []; end
if nargin < 3, source_dir = ''; end
if ~isstruct(cfg) || ~isfield(cfg, 'cache_directory') || isempty(cfg.cache_directory)
    info.reason = 'missing cfg.cache_directory';
    return
end
if ~get_cfg(cfg, 'use_cache', true)
    info.reason = 'use_cache=false';
    return
end
if ~isfinite(cap_usd) || cap_usd <= 0
    info.reason = 'nonfinite current cap';
    return
end

eta_file = fullfile(cfg.cache_directory, 'O1_eta_certificate_cache.mat');
recompute = logical(get_cfg(cfg, 'economic_eta_recompute', false));
if recompute || ~isfile(eta_file)
    [wrapper, ok, reason] = compute_eta_cache(cfg, source_dir, eta_file);
    if ~ok
        info.reason = reason;
        return
    end
else
    wrapper = load_eta_cache(eta_file);
    if ~isstruct(wrapper) || isempty(fieldnames(wrapper))
        info.reason = 'invalid eta cache';
        return
    end
end

[lower, info] = validate_eta_cache(wrapper, cfg, cap_usd, hash_fn);
end

% ======================================================================
function wrapper = load_eta_cache(file)
wrapper = struct();
try
    D = load(file);
catch exception
    wrapper = struct('load_error', exception.message);
    return
end
if isfield(D, 'eta_cache') && isstruct(D.eta_cache)
    wrapper = D.eta_cache;
elseif isfield(D, 'out') && isstruct(D.out)
    % Accept a bare 11_9 certificate file as a fallback.
    wrapper = struct('out', D.out, 'version', 1);
end
end

% ======================================================================
function [wrapper, ok, reason] = compute_eta_cache(cfg, source_dir, eta_file)
wrapper = struct();
ok = false;
reason = '';
if isempty(source_dir) || ~isfolder(source_dir)
    source_dir = find_partition_dir(cfg);
end
if isempty(source_dir) || ~isfolder(source_dir)
    reason = 'missing source partition context';
    return
end
try
    C = load(fullfile(source_dir, 'context.mat'), 'model', 'hour', 'z', 'meta');
    S = load(fullfile(source_dir, 'certificate.mat'), 'proof', 'context_signature');
catch exception
    reason = ['source load failed: ', exception.message];
    return
end
if ~all(isfield(C, {'model', 'hour', 'z', 'meta'})) || ...
        ~all(isfield(S, {'proof', 'context_signature'}))
    reason = 'source context/certificate fields missing';
    return
end
model = C.model;
hour = C.hour(:);
z = C.z(:);
T = numel(z);
n = numel(model.obj);
if numel(hour) ~= n || numel(z) ~= T
    reason = 'source context dimension mismatch';
    return
end
sense = model.sense(:);
pi0 = S.proof.pi(:);
if numel(pi0) ~= numel(model.rhs)
    reason = 'source price dimension mismatch';
    return
end
pi0(sense == '<') = min(0, pi0(sense == '<'));
pi0(sense == '>') = max(0, pi0(sense == '>'));
eta = get_cfg(cfg, 'economic_eta_eta', 0.03);
pi = pi0;
pi(numel(model.rhs)) = pi(numel(model.rhs)) + eta;
valid = isfinite(hour) & hour >= 1 & hour <= T + 1 & hour == round(hour);
pattern = spones(model.A);

levels = get_cfg(cfg, 'economic_eta_levels', [48 96 192]);
limits = get_cfg(cfg, 'economic_eta_limits', [60 180 600]);
threads = get_cfg(cfg, 'economic_eta_threads', 4);
seed = get_cfg(cfg, 'economic_eta_seed', 20261017);
allint = logical(get_cfg(cfg, 'economic_eta_allint', true));
reuse = logical(get_cfg(cfg, 'economic_eta_reuse_levels', true));
if numel(levels) ~= 3 || numel(limits) ~= 3
    reason = 'eta levels/limits must have 3 entries';
    return
end
if ~isequal(levels(:).', [48 96 192])
    reason = 'eta level hierarchy must be [48 96 192]';
    return
end

L = cell(1, 3);
for k = 1:3
    level_file = fullfile(cfg.cache_directory, ...
        sprintf('O1_eta_level%d.mat', levels(k)));
    if reuse && isfile(level_file)
        try
            Lk = load(level_file);
            if isfield(Lk, 'eta_prod')
                if abs(Lk.eta_prod - eta) > 1e-12
                    error('eta_prod mismatch');
                end
            elseif isfield(Lk, 'delta')
                if abs(Lk.delta - eta) > 1e-12
                    error('delta mismatch');
                end
            end
            if ~all(isfield(Lk, {'H', 'ell', 'lpx'})) || ...
                    numel(Lk.ell) ~= numel(Lk.lpx)
                error('level fields');
            end
            L{k} = Lk;
        catch exception
            reason = ['level cache invalid: ', exception.message];
            return
        end
    else
        ensure_gurobi('');
        try
            Lk = solve_level(model, pi, hour, z, levels(k), limits(k), ...
                seed, threads, valid, pattern, ...
                C.meta.original_intcon(:), allint && levels(k) == 192, eta);
        catch exception
            reason = ['level solve failed: ', exception.message];
            return
        end
        try
            save(level_file, '-struct', 'Lk', '-v7.3');
        catch
            % The level file is an accelerator; failing to persist it does
            % not invalidate the in-memory certificate.
        end
        L{k} = Lk;
    end
end

out = assemble3(model, pi, hour, z, valid, pattern, L{1}, L{2}, L{3});
out.base_cert = out.cert;
out.base_K = ceil(out.base_cert - 1e-5);
cut_k = out.base_K;
if cut_k <= 0 || cut_k > T
    reason = 'invalid cut target';
    return
end
A2 = [model.A; sparse(1, z, 1, 1, n)];
rhs2 = [model.rhs; cut_k];
sense2 = [model.sense(:); '>'];
model2 = model;
model2.A = A2;
model2.rhs = rhs2;
model2.sense = sense2;
pi_cut = zeros(numel(rhs2), 1);
pi_cut(end) = 1;
[part, ~] = partition_meta(model2, pi_cut, hour, z, 96);
out.lpx96_cut = zeros(part.K, 1);
out.ell96_cut = zeros(part.K, 1);
out.cut_k = cut_k;
out.pi_cut = pi_cut;
out.cert = part.B - part.guardB + ...
    sum(max(out.lpx96_cut, out.ell96_cut));
out.K_lower = ceil(out.cert - 1e-5);
out.method = '11_9 eta=0.03 + adaptive 48/96/192 + objective cut';
out.eta = eta;
out.guard = '1e-6+1e-9*(1+sum(abs(b*pi)))';

wrapper = struct('version', 1, 'out', out, ...
    'source_context_signature', S.context_signature, ...
    'source_model_signature', C.meta.model_signature, ...
    'source_cap_usd', C.meta.cap_usd, ...
    'source_cap_row', C.meta.cap_row, ...
    'eta', eta, 'method', out.method, ...
    'created', char(datetime('now')), ...
    'source', 'O1EtaCertificate recompute');
try
    eta_cache = wrapper;
    save(eta_file, 'eta_cache', '-v7.3');
catch
    % Keep the in-memory certificate; the next run can recompute.
end
ok = true;
end

% ======================================================================
function [lower, info] = validate_eta_cache(wrapper, cfg, cap_usd, hash_fn)
lower = -Inf;
info = struct('validated', false, 'reason', '', ...
    'source_context_signature', "", 'source_model_signature', "", ...
    'source_cap_usd', NaN, 'source_cap_row', NaN, 'eta', NaN, ...
    'cert', NaN, 'base_cert', NaN, 'cut_k', NaN, 'K_lower', NaN, ...
    'method', "", 'source', "");
required_wrapper = {'out', 'source_context_signature', ...
    'source_model_signature', 'source_cap_usd'};
if ~all(isfield(wrapper, required_wrapper))
    info.reason = 'eta cache missing wrapper fields';
    return
end
out = wrapper.out;
required_out = {'own', 'loc', 'K', 'B', 'guardB', 'cert48', 'cert96', ...
    'cert192', 'base_cert', 'cut_k', 'pi_cut', 'lpx96_cut', ...
    'ell96_cut', 'cert', 'K_lower', 'eta'};
if ~isstruct(out) || ~all(isfield(out, required_out))
    info.reason = 'eta cache missing certificate fields';
    return
end
if isfield(wrapper, 'load_error') && strlength(string(wrapper.load_error)) > 0
    info.reason = ['eta cache load failed: ', char(wrapper.load_error)];
    return
end

source_dir = fullfile(cfg.cache_directory, 'O1_partition21_v1', ...
    char(wrapper.source_context_signature));
if ~isfolder(source_dir)
    info.reason = 'source partition context directory missing';
    return
end
try
    C = load(fullfile(source_dir, 'context.mat'), 'model', 'hour', 'z', 'meta');
    S = load(fullfile(source_dir, 'certificate.mat'), 'proof', 'context_signature');
catch exception
    info.reason = ['source load failed: ', exception.message];
    return
end
model = C.model;
hour = C.hour(:);
z = C.z(:);
T = numel(z);
n = numel(model.obj);
if numel(hour) ~= n || numel(z) ~= T
    info.reason = 'source context dimension mismatch';
    return
end
if ~strcmp(char(S.context_signature), char(wrapper.source_context_signature))
    info.reason = 'source certificate signature mismatch';
    return
end
if ~isfield(C.meta, 'model_signature') || ...
        ~strcmp(char(C.meta.model_signature), char(wrapper.source_model_signature))
    info.reason = 'source model signature mismatch';
    return
end
if abs(C.meta.cap_usd - wrapper.source_cap_usd) > 1e-6
    info.reason = 'source cap mismatch';
    return
end
% The certificate is proved under the source cap.  A tighter current cap is
% a subset of that feasible set, so the same lower bound remains valid.
if cap_usd > wrapper.source_cap_usd + 1e-6
    info.reason = 'current cap is looser than certificate cap';
    return
end
if ~isempty(hash_fn)
    try
        current_hash = hash_fn(C.meta.model_signature, model.rhs);
        if ~strcmp(char(current_hash), char(wrapper.source_context_signature))
            info.reason = 'source context hash mismatch';
            return
        end
    catch exception
        info.reason = ['source hash failed: ', exception.message];
        return
    end
end

eta = out.eta;
if ~isfinite(eta) || abs(eta - wrapper.eta) > 1e-12
    info.reason = 'eta value mismatch';
    return
end
sense = model.sense(:);
pi0 = S.proof.pi(:);
if numel(pi0) ~= numel(model.rhs)
    info.reason = 'source price dimension mismatch';
    return
end
pi0(sense == '<') = min(0, pi0(sense == '<'));
pi0(sense == '>') = max(0, pi0(sense == '>'));
pi = pi0;
pi(numel(model.rhs)) = pi(numel(model.rhs)) + eta;

% ---- base certificate -------------------------------------------------
if numel(out.own) ~= n || max(out.own) ~= out.K || ...
        numel(out.loc) ~= out.K
    info.reason = 'base partition dimensions mismatch';
    return
end
groups = sparse(1:n, out.own, 1, n, out.K);
pattern = spones(model.A);
p = spones(pattern * groups);
cross = full(sum(p, 2)) ~= 1;
bp = model.rhs .* pi;
B = sum(bp(cross));
guardB = 1e-6 + 1e-9 * (1 + sum(abs(bp(cross))));
cert_base = B - guardB + sum(out.loc);
if abs(B - out.B) > 1e-6 * max(1, abs(B))
    info.reason = 'base B accounting mismatch';
    return
end
if abs(cert_base - out.base_cert) > 1e-7
    info.reason = 'base certificate arithmetic mismatch';
    return
end
if cert_base < max([out.cert48, out.cert96, out.cert192]) - 1e-6
    info.reason = 'base certificate weaker than a level';
    return
end

% ---- objective-cut certificate ---------------------------------------
A2 = [model.A; sparse(1, z, 1, 1, n)];
rhs2 = [model.rhs; out.cut_k];
sense2 = [model.sense(:); '>'];
model2 = model;
model2.A = A2;
model2.rhs = rhs2;
model2.sense = sense2;
pi_cut = out.pi_cut(:);
if numel(pi_cut) ~= numel(rhs2)
    info.reason = 'cut price dimension mismatch';
    return
end
pi_cut(sense2 == '<') = min(0, pi_cut(sense2 == '<'));
pi_cut(sense2 == '>') = max(0, pi_cut(sense2 == '>'));
if pi_cut(end) < -1e-12
    info.reason = 'cut dual sign violation';
    return
end
[part, ~] = partition_meta(model2, pi_cut, hour, z, 96);
if numel(out.lpx96_cut) ~= part.K || numel(out.ell96_cut) ~= part.K
    info.reason = 'cut local-bound dimensions mismatch';
    return
end
L = part.B - part.guardB + sum(max(out.lpx96_cut, out.ell96_cut));
if abs(L - out.cert) > 1e-8
    info.reason = 'cut certificate arithmetic mismatch';
    return
end
if L < out.cut_k - 1e-5
    info.reason = 'cut certificate below its own target';
    return
end
lower = ceil(out.cert - 1e-5);
if abs(lower - out.K_lower) > 1e-9
    info.reason = 'stored K_lower does not match certificate';
    return
end
if lower <= 0 || lower > T
    info.reason = 'invalid lower bound';
    return
end

info = struct('validated', true, 'reason', '', ...
    'source_context_signature', string(wrapper.source_context_signature), ...
    'source_model_signature', string(wrapper.source_model_signature), ...
    'source_cap_usd', wrapper.source_cap_usd, ...
    'source_cap_row', value_field(wrapper, 'source_cap_row', NaN), ...
    'eta', eta, 'cert', out.cert, 'base_cert', out.base_cert, ...
    'cut_k', out.cut_k, 'K_lower', lower, ...
    'method', string(value_field(wrapper, 'method', "eta_certificate")), ...
    'source', string(value_field(wrapper, 'source', "")));
end

% ======================================================================
function out = assemble3(model, pi, hour, z, ~, pattern, L48, L96, L192)
[P48, lp48] = partition_meta(model, pi, hour, z, 48);
[P96, lp96] = partition_meta(model, pi, hour, z, 96);
[P192, lp192] = partition_meta(model, pi, hour, z, 192);
assert(numel(L48.ell) == P48.K && numel(L96.ell) == P96.K && ...
    numel(L192.ell) == P192.K);
l48 = max(max(L48.lpx, lp48), L48.ell);
l96 = max(max(L96.lpx, lp96), L96.ell);
l192 = max(max(L192.lpx, lp192), L192.ell);
cert48 = P48.B - P48.guardB + sum(l48);
cert96 = P96.B - P96.guardB + sum(l96);
cert192 = P192.B - P192.guardB + sum(l192);
bp = model.rhs .* pi;

sel48 = find(P48.cross & ~P96.cross);
owner96 = row_owner(model, P96, sel48);
Bint48 = zeros(P96.K, 1);
choice48 = false(P96.K, 1);
V96 = l96;
for k = 1:P96.K
    kids = unique(P48.own(P96.cols{k}));
    if numel(kids) ~= 2, continue; end
    Bint48(k) = sum(bp(sel48(owner96 == k)));
    split = Bint48(k) + l48(kids(1)) + l48(kids(2));
    choice48(k) = split > l96(k) + 1e-12;
    V96(k) = max(l96(k), split);
end
sel96 = find(P96.cross & ~P192.cross);
owner192 = row_owner(model, P192, sel96);
Bint96 = zeros(P192.K, 1);
choice192 = false(P192.K, 1);
V192 = l192;
for j = 1:P192.K
    kids = unique(P96.own(P192.cols{j}));
    if numel(kids) ~= 2, continue; end
    Bint96(j) = sum(bp(sel96(owner192 == j)));
    split = Bint96(j) + V96(kids(1)) + V96(kids(2));
    choice192(j) = split > l192(j) + 1e-12;
    V192(j) = max(l192(j), split);
end

own_h = zeros(numel(model.obj), 1);
loc = [];
nid = 0;
for j = 1:P192.K
    cj = P192.cols{j};
    if choice192(j)
        kids96 = unique(P96.own(cj));
        for a = 1:numel(kids96)
            k = kids96(a);
            cj96 = P96.cols{k};
            if choice48(k)
                kids48 = unique(P48.own(cj96));
                for b = 1:numel(kids48)
                    nid = nid + 1;
                    idx = cj96(P48.own(cj96) == kids48(b));
                    own_h(idx) = nid;
                    loc(nid, 1) = l48(kids48(b)); %#ok<AGROW>
                end
            else
                nid = nid + 1;
                own_h(cj96) = nid;
                loc(nid, 1) = l96(k); %#ok<AGROW>
            end
        end
    else
        nid = nid + 1;
        own_h(cj) = nid;
        loc(nid, 1) = l192(j); %#ok<AGROW>
    end
end
assert(all(own_h > 0), 'unassigned variables');
groups = sparse(1:numel(model.obj), own_h, 1, numel(model.obj), nid);
p = spones(pattern * groups);
cross_h = full(sum(p, 2)) ~= 1;
B_h = sum(bp(cross_h));
guard_h = 1e-6 + 1e-9 * (1 + sum(abs(bp(cross_h))));
cert = B_h - guard_h + sum(loc);

% validity checks from the 11_9 assembly
Bexp = P192.B + sum(Bint96(choice192));
for j = find(choice192)'
    kids96 = unique(P96.own(P192.cols{j}));
    for a = 1:numel(kids96)
        k = kids96(a);
        if choice48(k)
            Bexp = Bexp + Bint48(k);
        end
    end
end
assert(abs(B_h - Bexp) <= 1e-6 * max(1, abs(B_h)), 'B accounting failed');
assert(cert >= max([cert48, cert96, cert192]) - 1e-6, ...
    'hybrid weaker than a level');
out = struct('cert', cert, 'cert48', cert48, 'cert96', cert96, ...
    'cert192', cert192, 'choice48', choice48, ...
    'choice192', choice192, 'Bint48', Bint48, 'Bint96', Bint96, ...
    'V96', V96, 'V192', V192, 'l48', l48, 'l96', l96, 'l192', l192, ...
    'own', own_h, 'loc', loc, 'B', B_h, 'guardB', guard_h, 'K', nid);
end

% ======================================================================
function L = solve_level(model, pi, hour, z, H, limit, seed, threads, ...
        ~, ~, intcon, allint, eta)
[part, lp] = partition_meta(model, pi, hour, z, H);
K = part.K;
ell = lp;
lpx = lp;
st = cell(K, 1);
tt = zeros(K, 1);
fprintf('level H=%d: K=%d blocks, limit=%.0fs\n', H, K, limit);
for j = 1:K
    cj = part.cols{j};
    ij = part.rows{j};
    local = struct('A', model.A(ij, cj), 'rhs', model.rhs(ij), ...
        'sense', model.sense(ij), 'obj', part.q(cj), ...
        'lb', model.lb(cj), 'ub', model.ub(cj), ...
        'vtype', repmat('C', numel(cj), 1), 'modelsense', 'min');
    gp = struct('TimeLimit', 10, 'Threads', threads, 'OutputFlag', 0, ...
        'FeasibilityTol', 1e-9, 'OptimalityTol', 1e-9);
    r = gurobi(local, gp);
    if strcmpi(r.status, 'OPTIMAL'), lpx(j) = r.objval; end
    if allint
        il = ismember(cj, intcon);
        isbin = model.lb(cj) == 0 & model.ub(cj) == 1;
        local.vtype(il & isbin) = 'B';
        local.vtype(il & ~isbin) = 'I';
    else
        local.vtype(ismember(cj, z)) = 'B';
    end
    gp = struct('TimeLimit', limit, 'Threads', threads, ...
        'OutputFlag', 0, 'MIPGap', 0, 'MIPGapAbs', 0, ...
        'FeasibilityTol', 1e-9, 'IntFeasTol', 1e-9, ...
        'OptimalityTol', 1e-9, 'Seed', seed);
    ts = tic;
    r = gurobi(local, gp);
    tt(j) = toc(ts);
    b = safe_bound(local, r);
    if isfinite(b) && b > ell(j), ell(j) = b; end
    st{j} = r.status;
    fprintf('  j=%3d/%d %-10s t=%5.1f gain=%7.3f cert=%10.4f\n', ...
        j, K, r.status, tt(j), ell(j) - lp(j), ...
        part.B - part.guardB + sum(ell));
end
L = struct('H', H, 'ell', ell, 'lpx', lpx, 'st', {st}, 'tt', tt, ...
    'limit', limit, 'eta_prod', eta);
L.cert = part.B - part.guardB + sum(ell);
fprintf('level H=%d done: cert=%.9f\n', H, L.cert);
end

% ======================================================================
function [part, lp] = partition_meta(model, pi, hour, z, H)
n = numel(model.obj);
T = numel(z);
K = ceil(T / H);
own = zeros(n, 1);
valid = isfinite(hour) & hour >= 1 & hour <= T + 1 & hour == round(hour);
own(valid) = floor((min(hour(valid), T) - 1) / H) + 1;
extra = find(~valid);
own(extra) = K + (1:numel(extra))';
K = K + numel(extra);
groups = sparse(1:n, own, 1, n, K);
pattern = spones(model.A);
p = spones(pattern * groups);
degree = full(sum(p, 2));
cross = degree ~= 1;
owner_row = full(p * (1:K)') ./ max(1, degree);
owner_row(cross) = 0;
cols = cell(K, 1);
rows = cell(K, 1);
for j = 1:K
    cols{j} = find(own == j);
    rows{j} = find(~cross & owner_row == j);
end
q = model.obj(:) - model.A(cross, :)' * pi(cross);
bp = model.rhs(cross) .* pi(cross);
B = sum(bp);
guardB = 1e-6 + 1e-9 * (1 + sum(abs(bp)));
box = max(abs(model.lb(:)), abs(model.ub(:)));
lp = zeros(K, 1);
for j = 1:K
    cj = cols{j};
    ij = rows{j};
    lbp = model.rhs(ij) .* pi(ij);
    gj = q(cj) - model.A(ij, cj)' * pi(ij);
    raw = sum(lbp) + sum(min(gj .* model.lb(cj), gj .* model.ub(cj)));
    guard = 1e-6 + 1e-9 * (1 + abs(raw) + sum(abs(lbp)) + ...
        sum(abs(gj) .* box(cj)));
    lp(j) = raw - guard;
end
part = struct('own', own, 'cols', {cols}, 'rows', {rows}, ...
    'cross', cross, 'q', q, 'lp', lp, 'B', B, 'guardB', guardB, ...
    'K', K);
end

% ======================================================================
function owner = row_owner(model, P, sel)
owner = zeros(numel(sel), 1);
for k = 1:numel(sel)
    c = find(model.A(sel(k), :), 1, 'first');
    owner(k) = P.own(c);
end
end

% ======================================================================
function safe = safe_bound(local, r)
safe = -Inf;
trusted = {'OPTIMAL', 'TIME_LIMIT', 'NODE_LIMIT', ...
    'ITERATION_LIMIT', 'SOLUTION_LIMIT', 'WORK_LIMIT', 'MEM_LIMIT', ...
    'INTERRUPTED', 'SUBOPTIMAL', 'USER_OBJ_LIMIT'};
if ~isfield(r, 'status') || ~any(strcmpi(r.status, trusted)), return; end
v = [];
for nm = {'objboundc', 'objbound'}
    if isfield(r, nm{1}) && isscalar(r.(nm{1})) && isfinite(r.(nm{1}))
        v(end + 1) = r.(nm{1}); %#ok<AGROW>
    end
end
if isempty(v), return; end
raw = min(v);
guard = 1e-6 + 1e-9 * (1 + abs(raw) + ...
    sum(abs(local.obj(:)) .* max(abs(local.lb(:)), abs(local.ub(:)))));
safe = raw - guard;
end

% ======================================================================
function ensure_gurobi(configured_dir)
if ~isempty(configured_dir), addpath(configured_dir); end
if ismember(exist('gurobi', 'file'), [2, 3]), return; end
gh = getenv('GUROBI_HOME');
if isempty(gh) && ispc
    [st, loc] = system('where gurobi_cl');
    if st == 0
        loc = splitlines(strtrim(loc));
        gh = fileparts(fileparts(char(loc(1))));
    end
end
if ~isempty(gh), addpath(fullfile(gh, 'matlab')); end
end

% ======================================================================
function d = find_partition_dir(cfg)
d = '';
root = fullfile(cfg.cache_directory, 'O1_partition21_v1');
if ~isfolder(root), return; end
items = dir(root);
for i = 1:numel(items)
    if ~items(i).isdir || any(strcmp(items(i).name, {'.', '..'}))
        continue
    end
    cand = fullfile(root, items(i).name);
    if isfile(fullfile(cand, 'context.mat')) && ...
            isfile(fullfile(cand, 'certificate.mat'))
        d = cand;
        return
    end
end
end

% ======================================================================
function v = get_cfg(s, name, default)
v = default;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end

% ======================================================================
function v = value_field(s, name, default)
v = default;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
