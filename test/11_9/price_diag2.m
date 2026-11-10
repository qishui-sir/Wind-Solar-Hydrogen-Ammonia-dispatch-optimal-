%% 11_9: second dual-price coordinate at H=96 (after eta_prod=0.03)
% For each candidate row r: forward LP change (exact local LPs) vs integer
% gain |g_r|*eps.  A positive net means a small step on that row improves the
% H=96 certificate.  Only sign-correct directions are tested.
clear; clc;
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cert_dir = fullfile(root,'src','cache','O1_partition21_v1','f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');
ensure_gurobi('');
S=load(fullfile(cert_dir,'certificate.mat')); C=load(fullfile(cert_dir,'context.mat'));
model=C.model; hour=C.hour(:); z=C.z(:); T=numel(z); sense=model.sense(:);
pi0=S.proof.pi(:); pi0(sense=='<')=min(0,pi0(sense=='<')); pi0(sense=='>')=max(0,pi0(sense=='>'));
eta=0.03; rprod=numel(model.rhs); pi1=pi0; pi1(rprod)=pi1(rprod)+eta;
pattern=spones(model.A); valid=isfinite(hour)&hour>=1&hour<=T+1&hour==round(hour);
H=96; [part,lp0]=partition_meta(model,pi1,hour,z,H,valid,pattern);
K=part.K; cross=part.cross; idx=find(cross); m=numel(idx); signs=sense(idx);
X=zeros(numel(model.obj),1); ell=lp0; lpx=lp0; st=cell(K,1);
for j=1:K
    cj=part.cols{j}; ij=part.rows{j};
    local=struct('A',model.A(ij,cj),'rhs',model.rhs(ij),'sense',sense(ij), ...
        'obj',part.q(cj),'lb',model.lb(cj),'ub',model.ub(cj), ...
        'vtype',repmat('C',numel(cj),1),'modelsense','min');
    gp=struct('TimeLimit',10,'Threads',4,'OutputFlag',0,'FeasibilityTol',1e-9,'OptimalityTol',1e-9);
    r=gurobi(local,gp); if strcmpi(r.status,'OPTIMAL'), lpx(j)=r.objval; end
    local.vtype(ismember(cj,z))='B';
    gp=struct('TimeLimit',120,'Threads',4,'OutputFlag',0,'MIPGap',0,'MIPGapAbs',0, ...
        'FeasibilityTol',1e-9,'IntFeasTol',1e-9,'OptimalityTol',1e-9,'Seed',20261017);
    r=gurobi(local,gp); b=safe_bound(local,r); if isfinite(b), ell(j)=max(ell(j),b); end
    st{j}=r.status; if isfield(r,'x')&&numel(r.x)==numel(cj), X(cj)=r.x; end
end
l=max(max(lp0,lpx),ell); cert0=part.B-part.guardB+sum(l); lp00=part.B-part.guardB+sum(max(lp0,lpx));
fprintf('H96 at pi1: cert=%.6f ceil=%d optimal=%d/%d\n',cert0,ceil(cert0-1e-5),nnz(strcmpi(st,'OPTIMAL')),K);
g=model.rhs(idx)-model.A(idx,:)*X;
fprintf('g: inf=%.4g l2=%.4g gcap=%.4g\n',norm(g,inf),norm(g),g(idx==C.meta.cap_row));
% top rows by |g|; test valid single-row ascent directions
[~,ord]=sort(abs(g),'descend');
fprintf('\n-- single-row directions (eps=1e-4) --\n');
eps=1e-4; found=0;
for kk=1:min(40,numel(ord))
    r=ord(kk); rr=idx(r); if rr==rprod, continue; end
    if signs(r)=='<'
        if pi1(rr)<0, vr=sign(g(r)); elseif pi1(rr)==0 && g(r)<0, vr=sign(g(r)); else, continue; end
    elseif signs(r)=='>'
        if pi1(rr)>0, vr=sign(g(r)); elseif pi1(rr)==0 && g(r)>0, vr=sign(g(r)); else, continue; end
    else
        vr=sign(g(r));
    end
    if vr==0, continue; end
    v=zeros(m,1); v(r)=vr;
    piP=pi1; piP(idx)=pi1(idx)+eps*v;
    lpP=lp_value(model,piP,hour,z,H,valid,pattern,sense);
    dLP=lpP-lp00; dInt=g'*(eps*v); net=dLP+dInt;
    fprintf('row %6d %s pi=%9.3g g=%9.3g dLP=%8.4f dInt=%8.4f net=%8.4f %s\n', ...
        rr,signs(r),pi1(rr),g(r),dLP,dInt,net,ternary(net>0,'<-- POSITIVE',''));
    found=found+(net>0);
end
fprintf('positive rows: %d\n',found);

function lp=lp_value(model,pi,hour,z,H,valid,pattern,sense)
pi(sense=='<')=min(0,pi(sense=='<')); pi(sense=='>')=max(0,pi(sense=='>'));
[part,lp]=partition_meta(model,pi,hour,z,H,valid,pattern);
K=part.K; lpx=lp;
for j=1:K
    cj=part.cols{j}; ij=part.rows{j};
    local=struct('A',model.A(ij,cj),'rhs',model.rhs(ij),'sense',sense(ij), ...
        'obj',part.q(cj),'lb',model.lb(cj),'ub',model.ub(cj), ...
        'vtype',repmat('C',numel(cj),1),'modelsense','min');
    gp=struct('TimeLimit',10,'Threads',4,'OutputFlag',0,'FeasibilityTol',1e-9,'OptimalityTol',1e-9);
    r=gurobi(local,gp);
    if strcmpi(r.status,'OPTIMAL'), lpx(j)=max(lp(j),r.objval); end
end
lp=part.B-part.guardB+sum(lpx);
end
function [part,lp]=partition_meta(model,pi,hour,z,H,valid,pattern)
n=numel(model.obj);T=numel(z);K=ceil(T/H);own=zeros(n,1);
own(valid)=floor((min(hour(valid),T)-1)/H)+1;
extra=find(~valid);own(extra)=K+(1:numel(extra))';K=K+numel(extra);
groups=sparse(1:n,own,1,n,K);p=spones(pattern*groups);degree=full(sum(p,2));
cross=degree~=1;owner=full(p*(1:K)')./max(1,degree);owner(cross)=0;
cols=cell(K,1);rows=cell(K,1);for j=1:K,cols{j}=find(own==j);rows{j}=find(~cross&owner==j);end
q=model.obj(:)-model.A(cross,:)'*pi(cross);bp=model.rhs(cross).*pi(cross);
B=sum(bp);guardB=1e-6+1e-9*(1+sum(abs(bp)));lp=zeros(K,1);
box=max(abs(model.lb(:)),abs(model.ub(:)));
for j=1:K
 cj=cols{j};ij=rows{j};lbp=model.rhs(ij).*pi(ij);gj=q(cj)-model.A(ij,cj)'*pi(ij);
 raw=sum(lbp)+sum(min(gj.*model.lb(cj),gj.*model.ub(cj)));
 guard=1e-6+1e-9*(1+abs(raw)+sum(abs(lbp))+sum(abs(gj).*box(cj)));
 lp(j)=raw-guard;
end
part=struct('own',own,'cols',{cols},'rows',{rows},'cross',cross,'q',q,'lp',lp,'B',B,'guardB',guardB,'K',K);
end
function s=ternary(c,a,b)
if c, s=a; else, s=b; end
end
function safe=safe_bound(local,r)
safe=-Inf; trusted={'OPTIMAL','TIME_LIMIT','NODE_LIMIT','ITERATION_LIMIT','SOLUTION_LIMIT','WORK_LIMIT','MEM_LIMIT','INTERRUPTED','SUBOPTIMAL','USER_OBJ_LIMIT'};
if ~isfield(r,'status')||~any(strcmpi(r.status,trusted)),return;end
v=[];for nm={'objboundc','objbound'},if isfield(r,nm{1})&&isscalar(r.(nm{1}))&&isfinite(r.(nm{1})),v(end+1)=r.(nm{1});end,end
if isempty(v),return;end
raw=min(v);guard=1e-6+1e-9*(1+abs(raw)+sum(abs(local.obj(:)).*max(abs(local.lb(:)),abs(local.ub(:)))));safe=raw-guard;
end
function ensure_gurobi(configured_dir)
if ~isempty(configured_dir),addpath(configured_dir);end
if ismember(exist('gurobi','file'),[2,3]),return;end
gh=getenv('GUROBI_HOME');
if isempty(gh)&&ispc,[st,loc]=system('where gurobi_cl');if st==0,loc=splitlines(strtrim(loc));gh=fileparts(fileparts(char(loc(1))));end,end
if ~isempty(gh),addpath(fullfile(gh,'matlab'));end
end
