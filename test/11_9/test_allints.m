%% 11_9: all-integer local MILP on selected H=192 hard blocks (eta=0.03)
clear; clc;
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cert_dir = fullfile(root,'src','cache','O1_partition21_v1','f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');
ensure_gurobi('');
S=load(fullfile(cert_dir,'certificate.mat')); C=load(fullfile(cert_dir,'context.mat'));
model=C.model; meta=C.meta; hour=C.hour(:); z=C.z(:); T=numel(z); sense=model.sense(:);
pi0=S.proof.pi(:); pi0(sense=='<')=min(0,pi0(sense=='<')); pi0(sense=='>')=max(0,pi0(sense=='>'));
eta=0.03; rprod=numel(model.rhs); pi=pi0; pi(rprod)=pi0(rprod)+eta;
pattern=spones(model.A); valid=isfinite(hour)&hour>=1&hour<=T+1&hour==round(hour);
H=192; [part]=partition_meta(model,pi,hour,z,H,valid,pattern);
L=load(fullfile(here,'level192.mat'));
intcon=meta.original_intcon(:);
blocks=[20 41 6 10];
for j=blocks
    cj=part.cols{j}; ij=part.rows{j};
    iz=ismember(cj,z); il=ismember(cj,intcon);
    isbin=model.lb(cj)==0 & model.ub(cj)==1;
    local=struct('A',model.A(ij,cj),'rhs',model.rhs(ij),'sense',sense(ij), ...
        'obj',part.q(cj),'lb',model.lb(cj),'ub',model.ub(cj), ...
        'vtype',repmat('C',numel(cj),1),'modelsense','min');
    local.vtype(iz)='B'; local.vtype(il&isbin)='B'; local.vtype(il&~isbin)='I';
    gp=struct('TimeLimit',600,'Threads',4,'OutputFlag',0,'MIPGap',0,'MIPGapAbs',0, ...
        'FeasibilityTol',1e-9,'IntFeasTol',1e-9,'OptimalityTol',1e-9,'Seed',20261017);
    ts=tic; r=gurobi(local,gp); el=toc(ts);
    b=safe_bound(local,r);
    fprintf('block=%2d allint status=%s t=%.1f bound=%.6f zonly=%.6f delta=%+.6f nint=%d\n', ...
        j,r.status,el,b,L.ell(j),b-L.ell(j),nnz(il));
end

function [part]=partition_meta(model,pi,hour,z,H,valid,pattern)
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
