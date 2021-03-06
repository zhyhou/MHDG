function [L L0 Lro Lf U U0 Uro Uf P P0 Pro Pf] = hdg_MappingProject(...
    flipFace,Nv,nv,Np,A,C)
% matrix multiplication to get the mapping

% number of elements
Ne = size(flipFace,1);

% initialization
L = zeros(4*Nv,6*nv,Ne);
L0 = zeros(4*Nv,1,Ne);
Lro = zeros(4*Nv,1,Ne);
Lf = Lro;
U = zeros(2*Nv,6*nv,Ne);
U0 = zeros(2*Nv,1,Ne);
Uro = zeros(2*Nv,1,Ne);
Uf = Uro;
P = zeros(Np,6*nv,Ne);
P0 = zeros(Np,1,Ne);
Pro = zeros(Np,1,Ne);
Pf = Pro;

% loop in elements
for iElem = 1:Ne
        
    % elemental matrices    
    Le = elementalMatrices(A(:,:,iElem),C(:,:,iElem));
    
    % local assembly indexes
    flipFace_e = flipFace(iElem,:);
    ind_1_v_L = (1:2*nv);
    ind_2_v_L = 2*nv + (1:2*nv);
    ind_3_v_L = 4*nv + (1:2*nv);
    
    if flipFace_e(1)
        Le(:,ind_1_v_L) = fliplr2(Le(:,ind_1_v_L));
    end
    if flipFace_e(2)
        Le(:,ind_2_v_L) = fliplr2(Le(:,ind_2_v_L));
    end
    if  flipFace_e(3)
        Le(:,ind_3_v_L) = fliplr2(Le(:,ind_3_v_L));
    end
    
    % store mapping
    L(:,:,iElem) = Le;
end

%% Elemental matrices
function LL= elementalMatrices(A,C)

% mapping for the velocity gradient
LL = A\C;

%% additional routines

function res = fliplr2(A)
% [ 1 1 1      [ 5 5 5 
%   2 2 2        6 6 6
%   3 3 3  ===>  3 3 3
%   4 4 4        4 4 4
%   5 5 5        1 1 1
%   6 6 6 ]      2 2 2 ]
res = zeros(size(A));
res(:,end-1:-2:1) = A(:,1:2:end-1);
res(:,end:-2:2) = A(:,2:2:end);

