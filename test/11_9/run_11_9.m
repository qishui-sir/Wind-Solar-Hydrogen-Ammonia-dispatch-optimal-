function run_11_9
%RUN_11_9  Adaptive three-level block-counting certificate for the Keco lower bound.
%
%   Valid claim:  Keco >= ceil(cert - 1e-5),
%   cert = B(P) - guardB + sum_j ell_j, where each ell_j is a valid local MILP
%   lower bound with all original variables continuous except z binary, and all
%   cross-block rows are dualized with the sign-correct certified prices pi.
%
%   At each level the partition is refined only where the two finer children
%   together are stronger than the merged block.  Every choice is a valid
%   partition, so the assembled certificate is valid (see the report).
%
%   Usage:  cd test/11_9; run_11_9
%   Set cfg.solve=true to recompute the levels from the stored context/certificate.

%   eta_prod is a DUAL PRICE shift on the annual equality row 192728.  It is
%   NOT the cost tolerance delta=0.5 of the Keco problem: the primal model,
%   the cost cap row and all A/rhs/sense/lb/ub are unchanged.  Only the
%   Lagrangian objective q = f - A_cross'*pi changes, so the local blocks are
%   re-solved to obtain valid bounds for the new dual price.  For any dual
%   price on an equality row the certificate stays valid; we take the max over
%   a few prices, which is still a valid lower bound for the ORIGINAL problem.

cfg = struct('H',[48 96 192], 'limit',[20 120 600], 'threads',4, 'seed',20261017, ...
    'solve',false, 'eta_prod',0.03, ...
    'files',{{'level48.mat','level96.mat','level192.mat'}}, ...
    'out','certificate_11_9.mat');

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cert_dir = fullfile(root,'src','cache','O1_partition21_v1', ...
    'f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');
ensure_gurobi('');
S = load(fullfile(cert_dir,'certificate.mat'));
C = load(fullfile(cert_dir,'context.mat'));
model = C.model; hour = C.hour(:); z = C.z(:); T = numel(z);
sense = model.sense(:); pi = S.proof.pi(:);
pi(sense=='<') = min(0,pi(sense=='<')); pi(sense=='>') = max(0,pi(sense=='>'));
pi0 = pi;
if isfield(cfg,'eta_prod') && cfg.eta_prod~=0
    rprod = numel(model.rhs);
    pi(rprod) = pi(rprod) + cfg.eta_prod;
end
dpi = pi - pi0;
assert(nnz(abs(dpi)>0)==1 && abs(dpi(numel(model.rhs))-cfg.eta_prod)<1e-12, ...
    'only the production-row dual price may change');
fprintf('Cost cap (TARGET): delta=0.5 USD/t, cap_usd=%.6f, cap_row=%d (UNCHANGED)\n', ...
    C.meta.cap_usd, C.meta.cap_row);
fprintf('Dual shift: pi(%d) += %.3f  (certificate only; no constraint change)\n', ...
    numel(model.rhs), cfg.eta_prod);
pattern = spones(model.A);
valid = isfinite(hour) & hour>=1 & hour<=T+1 & hour==round(hour);
fprintf('Stored certificate: best=%.6f  K_lower=%d\n', S.proof.best, S.proof.K_lower);

if ~cfg.solve && isfile(fullfile(here,cfg.out))
    D = load(fullfile(here,cfg.out)); out = D.out;
    verify(model,pi,pattern,out);
    return
end

L = cell(1,3);
for k = 1:3
    f = fullfile(here,cfg.files{k});
    if ~cfg.solve && isfile(f)
        L{k} = load(f);
        if isfield(L{k},'eta_prod')
            assert(abs(L{k}.eta_prod-cfg.eta_prod)<1e-12,'level eta mismatch');
        elseif isfield(L{k},'delta')
            assert(abs(L{k}.delta-cfg.eta_prod)<1e-12,'level eta mismatch');
        end
    else
        fprintf('Solving level H=%d (%.0f s/block) ...\n',cfg.H(k),cfg.limit(k));
        L{k} = solve_level(model,pi,hour,z,cfg.H(k),cfg.limit(k),cfg.seed,cfg.threads,valid,pattern);
        save(f,'-struct','L','-v7.3');
    end
end
out = assemble3(model,pi,hour,z,valid,pattern,L{1},L{2},L{3});
fprintf('\nLevel H=48 : cert=%.9f ceil=%d\n', out.cert48, ceil(out.cert48-1e-5));
fprintf('Level H=96 : cert=%.9f ceil=%d\n', out.cert96, ceil(out.cert96-1e-5));
fprintf('Level H=192: cert=%.9f ceil=%d\n', out.cert192, ceil(out.cert192-1e-5));
fprintf('Adaptive   : cert=%.9f ceil=%d  (192-split %d/46, 96-split %d/92)\n', ...
    out.cert, ceil(out.cert-1e-5), nnz(out.choice192), nnz(out.choice48));
fprintf('Gain over H=192: %.6f ; gain over stored K_lower: %d\n', ...
    out.cert-out.cert192, ceil(out.cert-1e-5)-S.proof.K_lower);
save(fullfile(here,cfg.out),'out','-v7.3');
end

% ======================================================================
function L = solve_level(model,pi,hour,z,H,limit,seed,threads,valid,pattern)
[part,lp] = partition_meta(model,pi,hour,z,H,valid,pattern);
K = part.K; ell = lp; lpx = lp; st = cell(K,1); tt = zeros(K,1);
fprintf('level H=%d: K=%d blocks, limit=%.0fs\n',H,K,limit);
for j = 1:K
    cj = part.cols{j}; ij = part.rows{j};
    local = struct('A',model.A(ij,cj),'rhs',model.rhs(ij),'sense',model.sense(ij), ...
        'obj',part.q(cj),'lb',model.lb(cj),'ub',model.ub(cj), ...
        'vtype',repmat('C',numel(cj),1),'modelsense','min');
    gp = struct('TimeLimit',10,'Threads',threads,'OutputFlag',0, ...
        'FeasibilityTol',1e-9,'OptimalityTol',1e-9);
    r = gurobi(local,gp);
    if strcmpi(r.status,'OPTIMAL'), lpx(j) = r.objval; end
    local.vtype(ismember(cj,z)) = 'B';
    gp = struct('TimeLimit',limit,'Threads',threads,'OutputFlag',0,'MIPGap',0, ...
        'MIPGapAbs',0,'FeasibilityTol',1e-9,'IntFeasTol',1e-9, ...
        'OptimalityTol',1e-9,'Seed',seed);
    ts = tic; r = gurobi(local,gp); tt(j) = toc(ts);
    b = safe_bound(local,r);
    if isfinite(b) && b > ell(j), ell(j) = b; end
    st{j} = r.status;
    fprintf('  j=%3d/%d %-10s t=%5.1f gain=%7.3f cert=%10.4f\n', ...
        j,K,r.status,tt(j),ell(j)-lp(j),part.B-part.guardB+sum(ell));
end
L = struct('H',H,'ell',ell,'lpx',lpx,'st',{st},'tt',tt,'limit',limit);
L.cert = part.B - part.guardB + sum(ell);
fprintf('level H=%d done: cert=%.9f\n',H,L.cert);
end

% ======================================================================
function out = assemble3(model,pi,hour,z,valid,pattern,L48,L96,L192)
[P48,lp48] = partition_meta(model,pi,hour,z,48,valid,pattern);
[P96,lp96] = partition_meta(model,pi,hour,z,96,valid,pattern);
[P192,lp192] = partition_meta(model,pi,hour,z,192,valid,pattern);
assert(numel(L48.ell)==P48.K && numel(L96.ell)==P96.K && numel(L192.ell)==P192.K);
l48 = max(max(L48.lpx,lp48),L48.ell);
l96 = max(max(L96.lpx,lp96),L96.ell);
l192 = max(max(L192.lpx,lp192),L192.ell);
cert48 = P48.B-P48.guardB+sum(l48);
cert96 = P96.B-P96.guardB+sum(l96);
cert192 = P192.B-P192.guardB+sum(l192);
bp = model.rhs.*pi;

sel48 = find(P48.cross & ~P96.cross); owner96 = row_owner(model,P96,sel48);
Bint48 = zeros(P96.K,1); choice48 = false(P96.K,1); V96 = l96;
for k = 1:P96.K
    kids = unique(P48.own(P96.cols{k}));
    if numel(kids)~=2, continue; end
    Bint48(k) = sum(bp(sel48(owner96==k)));
    split = Bint48(k)+l48(kids(1))+l48(kids(2));
    choice48(k) = split > l96(k)+1e-12;
    V96(k) = max(l96(k),split);
end
sel96 = find(P96.cross & ~P192.cross); owner192 = row_owner(model,P192,sel96);
Bint96 = zeros(P192.K,1); choice192 = false(P192.K,1); V192 = l192;
for j = 1:P192.K
    kids = unique(P96.own(P192.cols{j}));
    if numel(kids)~=2, continue; end
    Bint96(j) = sum(bp(sel96(owner192==j)));
    split = Bint96(j)+V96(kids(1))+V96(kids(2));
    choice192(j) = split > l192(j)+1e-12;
    V192(j) = max(l192(j),split);
end
own_h = zeros(numel(model.obj),1); loc = []; nid = 0;
for j = 1:P192.K
    cj = P192.cols{j};
    if choice192(j)
        kids96 = unique(P96.own(cj));
        for a = 1:numel(kids96)
            k = kids96(a); cj96 = P96.cols{k};
            if choice48(k)
                kids48 = unique(P48.own(cj96));
                for b = 1:numel(kids48)
                    nid = nid+1; idx = cj96(P48.own(cj96)==kids48(b));
                    own_h(idx) = nid; loc(nid,1) = l48(kids48(b)); %#ok<AGROW>
                end
            else
                nid = nid+1; own_h(cj96) = nid; loc(nid,1) = l96(k); %#ok<AGROW>
            end
        end
    else
        nid = nid+1; own_h(cj) = nid; loc(nid,1) = l192(j); %#ok<AGROW>
    end
end
assert(all(own_h>0),'unassigned variables');
groups = sparse(1:numel(model.obj),own_h,1,numel(model.obj),nid);
p = spones(pattern*groups); cross_h = full(sum(p,2))~=1;
B_h = sum(bp(cross_h)); guard_h = 1e-6+1e-9*(1+sum(abs(bp(cross_h))));
cert = B_h - guard_h + sum(loc);
% validity checks
Bexp = P192.B + sum(Bint96(choice192));
for j = find(choice192)'
    kids96 = unique(P96.own(P192.cols{j}));
    for a = 1:numel(kids96)
        k = kids96(a);
        if choice48(k), Bexp = Bexp + Bint48(k); end
    end
end
assert(abs(B_h-Bexp) <= 1e-6*max(1,abs(B_h)),'B accounting failed');
assert(cert >= max([cert48,cert96,cert192])-1e-6,'hybrid weaker than a level');
out = struct('cert',cert,'cert48',cert48,'cert96',cert96,'cert192',cert192, ...
    'choice48',choice48,'choice192',choice192,'Bint48',Bint48,'Bint96',Bint96, ...
    'V96',V96,'V192',V192,'l48',l48,'l96',l96,'l192',l192, ...
    'own',own_h,'loc',loc,'B',B_h,'guardB',guard_h,'K',nid);
end

% ======================================================================
function verify(model,pi,pattern,out)
n = numel(model.obj);
groups = sparse(1:n,out.own,1,n,out.K);
p = spones(pattern*groups); cross = full(sum(p,2))~=1;
bp = model.rhs.*pi; B = sum(bp(cross));
guard = 1e-6+1e-9*(1+sum(abs(bp(cross))));
cert = B - guard + sum(out.loc);
fprintf('Level H=48 : cert=%.9f ceil=%d\n', out.cert48, ceil(out.cert48-1e-5));
fprintf('Level H=96 : cert=%.9f ceil=%d\n', out.cert96, ceil(out.cert96-1e-5));
fprintf('Level H=192: cert=%.9f ceil=%d\n', out.cert192, ceil(out.cert192-1e-5));
fprintf('Adaptive   : cert=%.9f ceil=%d  (192-split %d/46, 96-split %d/92)\n', ...
    cert, ceil(cert-1e-5), nnz(out.choice192), nnz(out.choice48));
assert(abs(B-out.B) <= 1e-6*max(1,abs(B)),'recomputed B mismatch');
assert(abs(cert-out.cert) <= 1e-9,'recomputed cert mismatch');
assert(cert >= max([out.cert48,out.cert96,out.cert192])-1e-6,'cert weaker than a level');
end

% ======================================================================
function [part,lp] = partition_meta(model,pi,hour,z,H,valid,pattern)
n = numel(model.obj); T = numel(z); K = ceil(T/H); own = zeros(n,1);
own(valid) = floor((min(hour(valid),T)-1)/H)+1;
extra = find(~valid); own(extra) = K+(1:numel(extra))'; K = K+numel(extra);
groups = sparse(1:n,own,1,n,K); p = spones(pattern*groups);
degree = full(sum(p,2)); cross = degree~=1;
owner_row = full(p*(1:K)')./max(1,degree); owner_row(cross) = 0;
cols = cell(K,1); rows = cell(K,1);
for j = 1:K, cols{j} = find(own==j); rows{j} = find(~cross & owner_row==j); end
q = model.obj(:)-model.A(cross,:)'*pi(cross);
bp = model.rhs(cross).*pi(cross); B = sum(bp);
guardB = 1e-6+1e-9*(1+sum(abs(bp)));
box = max(abs(model.lb(:)),abs(model.ub(:))); lp = zeros(K,1);
for j = 1:K
    cj = cols{j}; ij = rows{j};
    lbp = model.rhs(ij).*pi(ij); gj = q(cj)-model.A(ij,cj)'*pi(ij);
    raw = sum(lbp)+sum(min(gj.*model.lb(cj),gj.*model.ub(cj)));
    guard = 1e-6+1e-9*(1+abs(raw)+sum(abs(lbp))+sum(abs(gj).*box(cj)));
    lp(j) = raw-guard;
end
part = struct('own',own,'cols',{cols},'rows',{rows},'cross',cross, ...
    'q',q,'lp',lp,'B',B,'guardB',guardB,'K',K);
end

function owner = row_owner(model,P,sel)
owner = zeros(numel(sel),1);
for k = 1:numel(sel)
    c = find(model.A(sel(k),:),1,'first');
    owner(k) = P.own(c);
end
end

function safe = safe_bound(local,r)
safe = -Inf;
trusted = {'OPTIMAL','TIME_LIMIT','NODE_LIMIT','ITERATION_LIMIT','SOLUTION_LIMIT', ...
    'WORK_LIMIT','MEM_LIMIT','INTERRUPTED','SUBOPTIMAL','USER_OBJ_LIMIT'};
if ~isfield(r,'status') || ~any(strcmpi(r.status,trusted)), return; end
v = [];
for nm = {'objboundc','objbound'}
    if isfield(r,nm{1}) && isscalar(r.(nm{1})) && isfinite(r.(nm{1}))
        v(end+1) = r.(nm{1}); %#ok<AGROW>
    end
end
if isempty(v), return; end
raw = min(v);
guard = 1e-6+1e-9*(1+abs(raw)+sum(abs(local.obj(:)).*max(abs(local.lb(:)),abs(local.ub(:)))));
safe = raw-guard;
end

function ensure_gurobi(configured_dir)
if ~isempty(configured_dir), addpath(configured_dir); end
if ismember(exist('gurobi','file'),[2,3]), return; end
gh = getenv('GUROBI_HOME');
if isempty(gh) && ispc
    [st,loc] = system('where gurobi_cl');
    if st==0, loc = splitlines(strtrim(loc)); gh = fileparts(fileparts(char(loc(1)))); end
end
if ~isempty(gh), addpath(fullfile(gh,'matlab')); end
end

