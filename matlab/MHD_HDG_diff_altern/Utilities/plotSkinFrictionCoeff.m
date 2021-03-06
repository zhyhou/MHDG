function plotSkinFrictionCoeff(L_grad,X,T,infoFaces,refEl,mu,nint,color)

exteriorFaces = [infoFaces.exteriorFaces_WALL_UP;infoFaces.exteriorFaces_WALL_DOWN];
Ne = size(T,1);
Np = size(refEl.NodesCoord,1);
elements = exteriorFaces(:,1);
faces = exteriorFaces(:,2);
faceNodes = refEl.faceNodes;
np1d = size(faceNodes,2);

% index for the velocity gradient
ind = bsxfun(@plus,Np*(elements'-1),faceNodes(faces,:)');

% index for the coordinates
T_t = T';
ind_x = T_t(ind);

% Vandermonde matrix
nDeg = refEl.degree;
V = Vandermonde_LP(nDeg,refEl.NodesCoord1d);
[L,U,P] = lu(V');

% Shape functions
z = -1 : 2/(nint-1) : 1;
shapeFunctions = zeros(nint,np1d,2);
for i = 1:nint
    x = z(i);
    [p,p_xi] = orthopoly1D_deriv(x,nDeg);
    N = U\(L\(P*[p,p_xi]));
    shapeFunctions(i,:,1) = N(:,1);
    shapeFunctions(i,:,2) = N(:,2);
end

% interpolate L
L_grad = transpose(reshape(L_grad,4,Ne*Np));
L_grad_xx = L_grad(:,1); L_grad_xy = L_grad(:,2);
L_grad_yx = L_grad(:,3); L_grad_yy = L_grad(:,4);
Lxx = shapeFunctions(:,:,1)*L_grad_xx(ind);
Lxy = shapeFunctions(:,:,1)*L_grad_xy(ind);
Lyx = shapeFunctions(:,:,1)*L_grad_yx(ind);
Lyy = shapeFunctions(:,:,1)*L_grad_yy(ind);
tau_xx = mu*2*Lxx;
tau_xy = mu*(Lxy + Lyx);
tau_yx = tau_xy;
tau_yy = mu*2*Lyy;

% interpolate X
x = X(:,1);
y = X(:,2);
x_int = shapeFunctions(:,:,1)*x(ind_x);
x_der = shapeFunctions(:,:,2)*x(ind_x);
y_der = shapeFunctions(:,:,2)*y(ind_x);

% normal and tangential vectors
xyDerNorm = sqrt(x_der.^2 + y_der.^2);
tx = x_der./xyDerNorm;
ty = y_der./xyDerNorm;
nx = -ty;
ny = tx;

% skin coefficient
skinCoeff = (tx.*tau_xx+ty.*tau_yx).*nx+(tx.*tau_xy+ty.*tau_yy).*ny;

% plot
plot(x_int,2*skinCoeff,[color '--'],'LineWidth',2)
xlim([0 1])
grid on