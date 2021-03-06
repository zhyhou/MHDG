!*****************************************
! project: MHDG
! file: hdg_magneticdependingmatrices.f90
! date: 29/05/2017
! Generate the matrices that depends on the
! magnetic field: for equilibrium evolving
! simulations
!*****************************************


SUBROUTINE HDG_magneticdependingmatrices()
  USE globals
  USE analytical
  USE LinearAlgebra
  USE printUtils
  USE MPI_OMP
  
  IMPLICIT NONE

  integer*4             :: iel,i,j,Ndim,Neq,Nel,Np,Nfp,Nf
  integer*4,allocatable :: ind_loc(:,:),perm(:)
  logical               :: F_dir_el(1:refEl%Nfaces)
  real*8                :: Xe(1:Mesh%Nnodesperelem,1:Mesh%Ndim)
  real*8,allocatable    :: Gel(:,:),Pel(:,:),Qel(:,:),Qfel(:,:),fe(:)
  IF (MPIvar%glob_id.eq.0) THEN
					IF (utils%printint>0) THEN
						WRITE(6,*) '*************************************************'
						WRITE(6,*) '*           MAGNETIC DEPENDING MATRICES         *'
						WRITE(6,*) '*************************************************' 
					END IF	   
		END IF
		
  Ndim        = Mesh%ndim
  Neq         = phys%Neq
  Nel         = Mesh%Nelems
  Np          = refEl%Nnodes2D
  Nfp         = refEl%Nfacenodes
  Nf          = refEl%Nfaces

  ALLOCATE(ind_loc(1:Nf,1:Neq*Nfp))
  ind_loc = 0
  DO i = 1,Nf
     DO j = 1,Neq*Nfp
        ind_loc(i,j) = Neq*Nfp*(i-1) + j
     END DO
  END DO

  ! Set perm for flipping faces
  ALLOCATE(perm(1:Neq*Nfp))
  perm = 0
  
  CALL set_permutations(Neq*Nfp,Neq,perm)

!!! !$OMP PARALLEL  DEFAULT(SHARED) &
!!! !$OMP PRIVATE(iel,Xe,F_dir_el,j,Pel,Gel,Qel,Qfel,fe)

  ALLOCATE(fe(1:Neq*Np))
  ALLOCATE(Pel(Neq*Np,Ndim*Neq*Np))
  ALLOCATE(Qel(Neq*Np,Ndim*Neq*Np))
  ALLOCATE(Qfel(Neq*Nf*Nfp,Neq*Ndim*Np))
  ALLOCATE(Gel(1:Neq*Np,1:Neq*Np))  
!*****************
! Loop in elements
!*****************  
!!! !$OMP DO SCHEDULE(STATIC)
  DO iel = 1,Nel
     Pel  = 0.
     Qel  = 0. 
     Gel  = 0.    
     Qfel = 0.
     fe   = 0.
     
     ! Coordinates of the nodes of the element
     Xe = Mesh%X(Mesh%T(iel,:),:)

     ! Dirichlet boundary conditions in the current element
     F_dir_el = Mesh%Fdir(iel,:)

     ! Compute the matrices for the element
     CALL elemental_matrices(iel,Xe,F_dir_el,Pel,Qel,Gel,Qfel,fe)
     ! Flip the faces for the elements for which the face is already been counted
     DO j = 1,Nf
        IF (Mesh%flipface(iel,j)) THEN
           Qfel(ind_loc(j,:),:) = Qfel(ind_loc(j,perm),:)           
        END if
     END DO

     ! Store the matrices for all the elements
     elMat%S(:,iel)    = fe
     elMat%P(:,:,iel)  = Pel-Qel
     elMat%Qf(:,:,iel) = Qfel
     elMat%G(:,:,iel)  = Gel
  END DO
!!! !$OMP END  DO
  DEALLOCATE(Pel,Qel,Qfel,fe)
!!! !$OMP END PARALLEL

  DEALLOCATE(ind_loc,perm)

  IF (MPIvar%glob_id.eq.0) THEN
					IF (utils%printint>0) THEN
						  WRITE(6,*) "Done!"
					END IF
  END IF
  
  
  CONTAINS
  

!*****************************************
! Elemental matrices computation: 2D case
!*****************************************
					SUBROUTINE elemental_matrices(iel,Xe,F_dir_el,Pel,Qel,Gel,Qfel,fe)
							integer*4,intent(IN)  :: iel
       real*8,intent(IN)     :: Xe(1:Mesh%Nnodesperelem,1:Mesh%Ndim)							
       logical,intent(IN)    :: F_dir_el(1:refEl%Nfaces)
       real*8,intent(INOUT)  :: Pel(:,:),Qel(:,:),Qfel(:,:),fe(:),Gel(:,:)
							integer*4             :: g,NGauss,ifa
							real*8                :: detJ,dvolu,dline,isdir,isext,xyDerNorm_g
							real*8                :: xy(1:refEl%Ngauss2d,1:ndim)
							real*8                :: xyf(1:refEl%Ngauss1d,1:ndim)
							real*8                :: xyDer(1:refEl%Ngauss1d,1:ndim)
							real*8                :: force(1:refEl%Ngauss2d,1:neq)
							real*8                :: Jacob(1:ndim,1:ndim)
							integer*4             :: ind_ff(neq*Nfp),ind_fe(neq*Nfp)
							real*8,allocatable    :: floc(:,:)
							real*8, parameter     :: tol = 1e-12
       integer*4             :: ind_fG(neq*ndim*Nfp)
       real*8,dimension(Np)  :: Nxg,Nyg,Nx_ax
       real*8                :: invJ(1:ndim,1:ndim),t_g(1:ndim),n_g(1:ndim)
       real*8                :: b(Mesh%Nnodesperelem,ndim),b_g(refEl%Ngauss2d,ndim)
       real*8                :: Bmod(Mesh%Nnodesperelem),Bmod_g(refEl%Ngauss2d)
       real*8                :: Bt(Mesh%Nnodesperelem),Bt_g(refEl%Ngauss2d)
       real*8                :: b_f(1:refEl%Ngauss1d,1:ndim)
       real*8                :: Nbn(1:Nfp)
       real*8                :: fluxg(refEl%Ngauss2d)
       real*8,allocatable,dimension(:,:)    :: Px,Py,Cn_loc,Qb_loc,Qbx,Qby,Cnx,Cny
#ifndef TEMPERATURE       
       real*8,allocatable,dimension(:,:)    ::Ge,Dre,Drifte
       real*8                :: divb,Bmod_x,Bmod_y,drift_x,drift_y
#endif
       !***********************************
       !    Volume computation
       !***********************************
							ALLOCATE(floc(1:Np,1:Neq))							
       ALLOCATE(Px(1:Np,1:Np))
       ALLOCATE(Py(1:Np,1:Np))
#ifndef TEMPERATURE       
       ALLOCATE(Ge(Np,Np))
       ALLOCATE(Dre(Np,Np))
       ALLOCATE(Drifte(Np*Neq,Np*Neq))
       Ge = 0.
       Drifte = 0.
       Dre = 0.     
       drift_x = 0.
       drift_y = 0.          
#endif       
       Px = 0.; Py = 0.
       floc = 0.d0      
       force   = 0.
       b       = 0.

							! Gauss points position
							xy = matmul(refEl%N2D,Xe)
					  
					  ! Magnetic field at nodes
					  Bmod   = sqrt(phys%Br(Mesh%T(iel,:))**2+phys%Bz(Mesh%T(iel,:))**2+phys%Bt(Mesh%T(iel,:))**2)
       b(:,1) = phys%Br(Mesh%T(iel,:))/Bmod
       b(:,2) = phys%Bz(Mesh%T(iel,:))/Bmod
       
       ! b, Bmod and Bt at Gauss points
       b_g    = matmul(refEl%N2D,b)
       Bmod_g = matmul(refEl%N2D,Bmod)
       Bt_g   = matmul(refEl%N2D,phys%Bt(Mesh%T(iel,:)))
						
							!! Some sources for West cases
				   fluxg = matmul(refEl%N2D,phys%flux2D(Mesh%T(iel,:)))
				   DO g=1,refEl%NGauss2D
										IF (switch%testcase==56) THEN
										   IF (fluxg(g).ge. 1.25 .and. fluxg(g).le. 1.3) THEN
										      force(g,1) = 3.811677788989013e-06
#ifdef TEMPERATURE
                force(g,3) = 18*3.811677788989013e-06
                force(g,4) = 18*3.811677788989013e-06
#endif
										   END IF
										   
										ELSE 
										   WRITE(6,*) "Error, test case not valid (only 56 coded for moving magnetic field so far...)"
										   STOP
										END IF
				   END DO
							!! end sources
	

							
							! Loop in 2D Gauss points
       Ngauss = refEl%NGauss2D
							DO g = 1,NGauss
 							
										! Jacobian										
										Jacob = 0.d0
										Jacob(1,1) = dot_product(refEl%Nxi2D(g,:),Xe(:,1))
										Jacob(1,2) = dot_product(refEl%Nxi2D(g,:),Xe(:,2))
										Jacob(2,1) = dot_product(refEl%Neta2D(g,:),Xe(:,1))
										Jacob(2,2) = dot_product(refEl%Neta2D(g,:),Xe(:,2))
										detJ = Jacob(1,1)*Jacob(2,2) - Jacob(1,2)*Jacob(2,1)
										IF (detJ < tol) THEN
										   error stop "Negative jacobian"
										END if

										! x and y derivatives of the shape functions
										call invert_matrix(Jacob,invJ)
							   Nxg = invJ(1,1)*refEl%Nxi2D(g,:) + invJ(1,2)*refEl%Neta2D(g,:)
							   Nyg = invJ(2,1)*refEl%Nxi2D(g,:) + invJ(2,2)*refEl%Neta2D(g,:)
							   IF (switch%axisym) THEN
							      Nx_ax = Nxg+1./xy(g,1)*refEl%N2D(g,:)
							   ELSE
							      Nx_ax = Nxg
							   END IF
							   
										! Integration weight
										dvolu = refEl%gauss_weights2D(g)*detJ
          IF (switch%axisym) THEN										
             dvolu = dvolu*xy(g,1)
          END IF
          
#ifndef TEMPERATURE      
          ! Divergence of b at the Gauss points
          divb = dot_product(Nx_ax,b(:,1))+dot_product(Nyg,b(:,2))
    
          ! Drift at Gauss points
          IF (switch%driftvel) THEN
						       Bmod_x  = dot_product(Nxg,Bmod)
						       Bmod_y  = dot_product(Nyg,Bmod)
						       drift_x =  phys%dfcoef*Bt_g(g)*Bmod_y/Bmod_g(g)**3
						       drift_y = -phys%dfcoef*Bt_g(g)*Bmod_x/Bmod_g(g)**3
          END IF
#endif          
										! Contribution of the current integration point to the elemental matrix
          Px = Px + TensorProduct(Nxg-b_g(g,1)*(b_g(g,1)*Nxg+b_g(g,2)*Nyg),refEl%N2D(g,:))*dvolu
          Py = Py + TensorProduct(Nyg-b_g(g,2)*(b_g(g,1)*Nxg+b_g(g,2)*Nyg),refEl%N2D(g,:))*dvolu
#ifndef TEMPERATURE           
          Ge = Ge - phys%a*divb*TensorProduct(refEl%N2D(g,:),refEl%N2D(g,:))*dvolu
          Dre = Dre + TensorProduct(refEl%N2D(g,:),( Nxg*drift_x+ Nyg*drift_y ))*dvolu
#endif          
				      floc = floc + tensorProduct(refEl%N2D(g,:),force(g,:))*dvolu
							END DO

							fe = reshape(transpose(floc),(/Neq*Np/))
       CALL expand_matrix_Bt(Px,Py,Pel)
#ifndef TEMPERATURE       
       CALL expand_matrix(Dre,Neq,Drifte)
       CALL expand_matrix_G(Ge,Gel)
       Gel = Gel + Drifte
       DEALLOCATE(Ge,Drifte,Dre)
#endif         
       !***********************************
  					! Faces computations
       !***********************************
							NGauss = refEl%Ngauss1D
       ALLOCATE(Cn_loc(Neq*Ndim*Nfp,Neq*Nfp))
       ALLOCATE(Qb_loc(Neq*Nfp,Ndim*Neq*Nfp))
       ALLOCATE(Qbx(Nfp,Nfp))
       ALLOCATE(Qby(Nfp,Nfp))
       ALLOCATE(Cnx(Nfp,Nfp))
       ALLOCATE(Cny(Nfp,Nfp))       
       Qb_loc = 0.						
							Cn_loc = 0.
							
       ! Loop in the faces of the element
							DO ifa = 1,Nf

          ! Set isdir for Dirichlet faces and 
          ! isext for exterior faces
          isdir = 0.
          isext = 0.
          IF (F_dir_el(ifa)) isdir = 1.
#ifdef PARALL          
! probably useless, to be verified
          IF ( (Mesh%F(iel,ifa).gt.Mesh%Nintfaces)  ) THEN
             IF (Mesh%boundaryFlag(Mesh%F(iel,ifa)-Mesh%Nintfaces).ne.0) THEN
                isext = 1.
             END IF
          ENDIF 
#else
          IF (Mesh%F(iel,ifa) > Mesh%Nintfaces ) isext = 1.
#endif          
          ind_fG = reshape(tensorSumInt( (/ (i, i = 1, neq*ndim) /),neq*ndim*(refEl%face_nodes(ifa,:)-1) ) , (/neq*ndim*Nfp/))
          ind_fe = reshape(tensorSumInt( (/ (i, i = 1, neq) /),neq*(refEl%face_nodes(ifa,:)-1) ) , (/neq*Nfp/))
          ind_ff = (ifa-1)*neq*Nfp + (/ (i, i = 1, neq*Nfp) /)
										xyf    = matmul(refEl%N1D,Xe(refEl%face_nodes(ifa,:),:))
          xyDer  = matmul(refEl%Nxi1D,Xe(refEl%face_nodes(ifa,:),:))
          
										! b at faces Gauss points
										b_f    = matmul(refEl%N1D,b(refEl%face_nodes(ifa,:),:))
										   
										Qbx = 0.; Qby = 0.  
										Cnx = 0.; Cny = 0.
										
										! Loop in 1D Gauss points
										DO g = 1,NGauss
										
										   ! Calculate the integration weight
										   xyDerNorm_g = norm2(xyDer(g,:))
										   dline = refEl%gauss_weights1D(g)*xyDerNorm_g

						       IF (switch%axisym) THEN										
						          dline = dline*xyf(g,1)
						       END IF
										   ! Unit normal to the boundary
										   t_g = xyDer(g,:)/xyDerNorm_g
										   n_g = [t_g(2), -t_g(1)]
										   
										   ! Contribution of the current integration point to the elemental matrix
             Nbn = refEl%N1D(g,:)*( b_f(g,1)*n_g(1)+b_f(g,2)*n_g(2) )
             Qbx = Qbx + b_f(g,1)*tensorProduct(refEl%N1D(g,:),Nbn)*dline
             Qby = Qby + b_f(g,2)*tensorProduct(refEl%N1D(g,:),Nbn)*dline    
             Cnx = Cnx + tensorProduct(refEl%N1D(g,:),refEl%N1D(g,:))*n_g(1)*dline
             Cny = Cny + tensorProduct(refEl%N1D(g,:),refEl%N1D(g,:))*n_g(2)*dline 
										END DO

										! Elemental assembly
          CALL expand_matrix_Bt(Qbx,Qby,Qb_loc)
          CALL expand_matrix_B(Cnx,Cny,Cn_loc)
          Qel(ind_fe,ind_fG) = Qel(ind_fe,ind_fG) + transpose(Cn_loc) - Qb_loc
          Qfel(ind_ff,ind_fG)  = Qfel(ind_ff,ind_fG) + Qb_loc*(1-isext)
										
							END DO

      CALL multiply_for_diffusion(Qfel)
      CALL multiply_for_diffusion(Pel)
      CALL multiply_for_diffusion(Qel)  
      DEALLOCATE(Px,Py,Qb_loc,Qbx,Qby)
      
					END SUBROUTINE elemental_matrices				
					
													
!*******************************************
!           AUXILIARY ROUTINES
!*******************************************

									
								!*******************************************
								! Expand matrix
								!*******************************************									
								SUBROUTINE expand_matrix(A,n,B)
										integer*4,intent(in) :: n
										real*8,intent(in)    :: A(:,:)
										real*8,intent(out)   :: B(1:n*size(A,1),1:n*size(A,1))
										integer*4            :: i,j,k,m
										
										m = size(A,1)
										B = 0.d0
										DO i = 1,m
													DO j = 1,m
													   DO k =1,n
													      B(n*(i-1)+k,n*(j-1)+k) = A(i,j)
													   END DO
													END DO
										END DO
								END SUBROUTINE expand_matrix
								
								





        !*******************************************
        ! Expand matrix B
        !*******************************************
        SUBROUTINE expand_matrix_B(Bx,By,B)
          real*8,intent(in)    :: Bx(:,:),By(:,:)
          real*8,intent(out)   :: B(1:Neq*Ndim*size(Bx,1),1:Neq*size(Bx,2))
          integer*4            :: i,j,k,n,m

          n = size(Bx,1)
          m = size(Bx,2)
          B = 0.d0
          DO j= 1,m
             DO i = 1,n
                DO k = 1,Neq
                   B((i-1)*Neq*Ndim+1+(k-1)*Ndim,(j-1)*Neq+k) = Bx(i,j)
                   B((i-1)*Neq*Ndim+2+(k-1)*Ndim,(j-1)*Neq+k) = By(i,j)
!                B((i-1)*4+1,(j-1)*2+1) = Bx(i,j)
!                B((i-1)*4+2,(j-1)*2+1) = By(i,j)
!                B((i-1)*4+3,(j-1)*2+2) = Bx(i,j)
!                B((i-1)*4+4,(j-1)*2+2) = By(i,j)
                END DO
             END DO
          END DO
        END SUBROUTINE expand_matrix_B



        !*******************************************
        ! Expand matrix B transpose
        !*******************************************
        SUBROUTINE expand_matrix_Bt(Bx,By,B)
          real*8,intent(in)    :: Bx(:,:),By(:,:)
          real*8,intent(out)   :: B(1:Neq*size(Bx,1),1:Neq*Ndim*size(Bx,2))
          integer*4            :: i,j,k,n,m

          n = size(Bx,1)
          m = size(Bx,2)
          B = 0.d0
          DO j = 1,m
             DO i = 1,n
                DO k=1,Neq
                   B((i-1)*Neq+k,(j-1)*Neq*Ndim+1+(k-1)*Ndim) = Bx(i,j)
                   B((i-1)*Neq+k,(j-1)*Neq*Ndim+2+(k-1)*Ndim) = By(i,j)
!                B((i-1)*2+1,(j-1)*4+1) = Bx(i,j)
!                B((i-1)*2+1,(j-1)*4+2) = By(i,j)
!                B((i-1)*2+2,(j-1)*4+3) = Bx(i,j)
!                B((i-1)*2+2,(j-1)*4+4) = By(i,j)
                END DO
             END DO
          END DO
        END SUBROUTINE expand_matrix_Bt





								
!OLD ROUTINES								
								!*******************************************
								! Expand matrix B
								!*******************************************									
!								SUBROUTINE expand_matrix_B(Bx,By,B)
!										real*8,intent(in)    :: Bx(:,:),By(:,:)
!										real*8,intent(out)   :: B(1:4*size(Bx,1),1:2*size(Bx,2))
!										integer*4            :: i,j,n,m
!										
!										n = size(Bx,1)
!										m = size(Bx,2)
!										B = 0.d0
!										DO j= 1,m
!													DO i = 1,n
!																B((i-1)*4+1,(j-1)*2+1) = Bx(i,j)
!																B((i-1)*4+2,(j-1)*2+1) = By(i,j)
!																B((i-1)*4+3,(j-1)*2+2) = Bx(i,j)
!																B((i-1)*4+4,(j-1)*2+2) = By(i,j)
!													END DO
!										END DO
!								END SUBROUTINE expand_matrix_B								
								


								!*******************************************
								! Expand matrix B transpose
								!*******************************************									
!								SUBROUTINE expand_matrix_Bt(Bx,By,B)
!										real*8,intent(in)    :: Bx(:,:),By(:,:)
!										real*8,intent(out)   :: B(1:2*size(Bx,1),1:4*size(Bx,2))
!										integer*4            :: i,j,n,m
!										
!										n = size(Bx,1)
!										m = size(Bx,2)
!										B = 0.d0
!										DO j = 1,m
!													DO i = 1,n
!																B((i-1)*2+1,(j-1)*4+1) = Bx(i,j)
!																B((i-1)*2+1,(j-1)*4+2) = By(i,j)
!																B((i-1)*2+2,(j-1)*4+3) = Bx(i,j)
!																B((i-1)*2+2,(j-1)*4+4) = By(i,j)
!													END DO
!										END DO
!								END SUBROUTINE expand_matrix_Bt					
								
								

								!*******************************************
								! Expand matrix G
								!*******************************************									
								SUBROUTINE expand_matrix_G(Gl,G)
										real*8,intent(in)    :: Gl(:,:)
										real*8,intent(inout) :: G(1:2*size(Gl,1),1:2*size(Gl,2))
										integer*4            :: i,j,n,m
										
										n = size(Gl,1)
										m = size(Gl,2)
				      DO i=1,n
				         DO j=1,m
				           G((i-1)*2+2,(j-1)*2+1) = G((i-1)*2+2,(j-1)*2+1) + Gl(i,j)
				         END DO
				      END DO
								END SUBROUTINE expand_matrix_G	
															
								
     
							!*****************************************
							! Set permutations for flipping faces
							!****************************************     
							 SUBROUTINE set_permutations(n,m,perm)
							 integer, intent(IN)  :: n,m
							 integer, intent(OUT) :: perm(:)
							 integer              :: i
							 integer              :: temp(m,n/m),templr(m,n/m)

							 IF (mod(n,m) .ne. 0) then
							    WRITE(6,*) 'Error! n must be a multiple of m'
							    STOP
							 END IF

							 templr = 0
							 temp = reshape( (/ (i, i = 1, n) /), (/ m, n/m /) )
							 DO i = 1,n/m
							    templr(:,i) = temp(:,n/m-i+1)
							 END DO
							 perm = reshape(templr,(/n/))
							 END SUBROUTINE set_permutations     
     
     
       SUBROUTINE multiply_for_diffusion(mat)
       real*8, intent(inout) :: mat(:,:)
       integer               :: n,i
       n = size(mat,1)/Neq
       DO i = 1,n
          mat((i-1)*Neq+1,:) = mat((i-1)*Neq+1,:)*phys%diff_n
          mat((i-1)*Neq+2,:) = mat((i-1)*Neq+2,:)*phys%diff_u
#ifdef TEMPERATURE
          mat((i-1)*Neq+3,:) = mat((i-1)*Neq+3,:)*phys%diff_e
          mat((i-1)*Neq+4,:) = mat((i-1)*Neq+4,:)*phys%diff_ee
#endif
       END DO
       END SUBROUTINE multiply_for_diffusion
END SUBROUTINE HDG_magneticdependingmatrices




