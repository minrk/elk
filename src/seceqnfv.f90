
! Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.

!BOP
! !ROUTINE: seceqnfv
! !INTERFACE:
subroutine seceqnfv(nmatp,ngp,igpig,vgpc,apwalm,evalfv,evecfv)
! !USES:
use modmain
! !INPUT/OUTPUT PARAMETERS:
!   nmatp  : order of overlap and Hamiltonian matrices (in,integer)
!   ngp    : number of G+k-vectors for augmented plane waves (in,integer)
!   igpig  : index from G+k-vectors to G-vectors (in,integer(ngkmax))
!   vgpc   : G+k-vectors in Cartesian coordinates (in,real(3,ngkmax))
!   apwalm : APW matching coefficients
!            (in,complex(ngkmax,apwordmax,lmmaxapw,natmtot))
!   evalfv : first-variational eigenvalues (out,real(nstfv))
!   evecfv : first-variational eigenvectors (out,complex(nmatmax,nstfv))
! !DESCRIPTION:
!   Solves the secular equation,
!   $$ (H-\epsilon O)b=0, $$
!   for the all the first-variational states of the input $k$-point.
!
! !REVISION HISTORY:
!   Created March 2004 (JKD)
!EOP
!BOC
implicit none
! arguments
integer, intent(in) :: nmatp
integer, intent(in) :: ngp
integer, intent(in) :: igpig(ngkmax)
real(8), intent(in) :: vgpc(3,ngkmax)
complex(8), intent(in) :: apwalm(ngkmax,apwordmax,lmmaxapw,natmtot)
real(8), intent(out) :: evalfv(nstfv)
complex(8), intent(out) :: evecfv(nmatmax,nstfv)
! local variables
integer is,ia,i,m,np
integer lwork,info
real(8) v(1),vl,vu
real(8) ts0,ts1
! allocatable arrays
integer, allocatable :: iwork(:)
integer, allocatable :: ifail(:)
real(8), allocatable :: w(:)
real(8), allocatable :: rwork(:)
complex(8), allocatable :: h(:)
complex(8), allocatable :: o(:)
complex(8), allocatable :: work(:)
if (tpmat) then
  np=(nmatp*(nmatp+1))/2
else
  np=nmatp**2
end if
!-----------------------------------------------!
!     Hamiltonian and overlap matrix set up     !
!-----------------------------------------------!
call timesec(ts0)
allocate(h(np),o(np))
!$OMP PARALLEL SECTIONS DEFAULT(SHARED) PRIVATE(is,ia)
!$OMP SECTION
! Hamiltonian
h(:)=0.d0
do is=1,nspecies
  do ia=1,natoms(is)
    call hmlaa(.false.,is,ia,ngp,apwalm,v,h)
    call hmlalo(.false.,is,ia,ngp,apwalm,v,h)
    call hmllolo(.false.,is,ia,ngp,v,h)
  end do
end do
call hmlistl(.false.,ngp,igpig,vgpc,v,h)
!$OMP SECTION
! overlap
o(:)=0.d0
do is=1,nspecies
  do ia=1,natoms(is)
    call olpaa(.false.,is,ia,ngp,apwalm,v,o)
    call olpalo(.false.,is,ia,ngp,apwalm,v,o)
    call olplolo(.false.,is,ia,ngp,v,o)
  end do
end do
call olpistl(.false.,ngp,igpig,v,o)
!$OMP END PARALLEL SECTIONS
call timesec(ts1)
!$OMP CRITICAL
timemat=timemat+ts1-ts0
!$OMP END CRITICAL
!------------------------------------!
!     solve the secular equation     !
!------------------------------------!
call timesec(ts0)
allocate(iwork(5*nmatp))
allocate(ifail(nmatp))
allocate(w(nmatp))
allocate(rwork(7*nmatp))
lwork=2*nmatp
allocate(work(lwork))
if (tpmat) then
! packed matrix storage
  call zhpgvx(1,'V','I','U',nmatp,h,o,vl,vu,1,nstfv,evaltol,m,w,evecfv, &
   nmatmax,work,rwork,iwork,ifail,info)
  evalfv(1:nstfv)=w(1:nstfv)
  if (info.ne.0) goto 10
else
! upper triangular matrix storage
  call zhegvx(1,'V','I','U',nmatp,h,nmatp,o,nmatp,vl,vu,1,nstfv,evaltol,m,w, &
   evecfv,nmatmax,work,lwork,rwork,iwork,ifail,info)
  evalfv(1:nstfv)=w(1:nstfv)
  if (info.ne.0) goto 10
end if
call timesec(ts1)
!$OMP CRITICAL
timefv=timefv+ts1-ts0
!$OMP END CRITICAL
deallocate(iwork,ifail,w,rwork,h,o,work)
return
10 continue
write(*,*)
write(*,'("Error(seceqnfv): diagonalisation failed")')
write(*,'(" ZHPGVX/ZHEGVX returned INFO = ",I8)') info
if (info.gt.nmatp) then
  i=info-nmatp
  write(*,'(" The leading minor of the overlap matrix of order ",I8)') i
  write(*,'("  is not positive definite")')
  write(*,'(" Order of overlap matrix : ",I8)') nmatp
  write(*,*)
end if
stop
end subroutine
!EOC

