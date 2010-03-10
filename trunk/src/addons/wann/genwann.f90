subroutine genwann(ikloc,evecfv,evecsv)
use modmain
use mod_mpi_grid
implicit none
! arguments
integer, intent(in) :: ikloc
complex(8), intent(in) :: evecfv(nmatmax,nstfv)
complex(8), intent(in) :: evecsv(nstsv,nstsv)
! local variables
complex(8), allocatable :: apwalm(:,:,:,:)
complex(8), allocatable :: wfsvmt(:,:,:,:,:)
complex(8), allocatable :: wfsvit(:,:,:)
!complex(8), allocatable :: wann_unkmt_new(:,:,:,:,:)
!complex(8), allocatable :: wann_unkit_new(:,:,:)
integer j,n
integer :: ik

ik=mpi_grid_map(nkpt,dim_k,loc=ikloc)
! allocate arrays
allocate(wfsvmt(lmmaxvr,nrfmax,natmtot,nspinor,nstsv))
!allocate(wfsvit(ngkmax,nspinor,nstsv))
allocate(apwalm(ngkmax,apwordmax,lmmaxapw,natmtot))
call match(ngk(1,ik),gkc(1,1,ikloc),tpgkc(1,1,1,ikloc),sfacgk(1,1,1,ikloc),apwalm)
! generate second-varioational wave-functions
call genwfsvmt(lmaxvr,lmmaxvr,ngk(1,ik),evecfv,evecsv,apwalm,wfsvmt)
!call genwfsvit(ngk(1,ik),evecfv,evecsv,wfsvit)
! calculate WF expansion coefficients
call genwann_c(ik,evalsv(1,ik),wfsvmt,wann_c(1,1,ikloc))
! compute Bloch-sums of Wannier functions
!allocate(wann_unkmt_new(lmmaxvr,nrfmax,natmtot,nspinor,nwann))
!allocate(wann_unkit_new(ngkmax,nspinor,nwann))
!wann_unkmt_new=zzero
!wann_unkit_new=zzero
!do n=1,nwann
!  do j=1,nstsv
!    wann_unkmt_new(:,:,:,:,n)=wann_unkmt_new(:,:,:,:,n) + &
!      wfsvmt(:,:,:,:,j)*wann_c(n,j,ikloc)
!    wann_unkit_new(:,:,n)=wann_unkit_new(:,:,n) + &
!      wfsvit(:,:,j)*wann_c(n,j,ikloc)
!  enddo
!enddo
!wann_unkmt(:,:,:,:,:,ikloc)=wann_unkmt_new(:,:,:,:,:)
!wann_unkit(:,:,:,ikloc)=wann_unkit_new(:,:,:)
deallocate(wfsvmt,apwalm)
return
end


