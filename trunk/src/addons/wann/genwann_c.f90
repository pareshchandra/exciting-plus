subroutine genwann_c(ik,e,wfsvmt,wann_c_)
use modmain
implicit none
! arguments
integer, intent(in) :: ik
real(8), intent(in) :: e(nstsv)
complex(8), intent(in) :: wfsvmt(lmmaxvr,nrfmax,natmtot,nspinor,nstsv)
complex(8), intent(out) :: wann_c_(nwann,nstsv)
! local variables
complex(8), allocatable :: prjao(:,:)
complex(8), allocatable :: s(:,:),sdiag(:)
integer ispn,j,n,m1,m2,ias,lm,ierr,itype
integer itr(3),i,iw
real(8) tr(3),d1
!integer, allocatable :: wann_nint_tmp(:,:)
complex(8) zt1
logical, external :: bndint

!allocate(wann_nint_tmp(2,wann_ntype))
!wann_nint_tmp=wann_nint
!10 continue
! compute <\psi|g_n>
allocate(prjao(nwann,nstsv))
prjao=zzero
do n=1,nwann
  if (.not.wannier_lc) then
    ias=iwann(1,n)
    lm=iwann(2,n)
    ispn=iwann(3,n)
    itype=iwann(4,n)
    do j=1,nstsv
      if (bndint(j,e(j),wann_eint(1,itype),wann_eint(2,itype))) then
        call genprjao(ias,lm,ispn,j,wfsvmt,prjao(n,j))
      endif
    enddo
  else
    do i=1,wann_iorb_lc(0,1,n)
      d1=wann_iorb_lcc(i,n)
      iw=wann_iorb_lc(i,1,n)
      itr(:)=wann_iorb_lc(i,2:4,n)
      tr(:)=avec(:,1)*itr(1)+avec(:,2)*itr(2)+avec(:,3)*itr(3)
      ias=iwann(1,iw)
      lm=iwann(2,iw)
      ispn=iwann(3,iw)
      itype=iwann(4,iw)
      do j=1,nstsv
        if (bndint(j,e(j),wann_eint(1,itype),wann_eint(2,itype))) then
          call genprjao(ias,lm,ispn,j,wfsvmt,zt1)
! <psi_k(r)|g(r-T)>=<psi(r+T)|g(r)>=e^{-ikT}<psi(r)|g(r)>
          prjao(n,j)=prjao(n,j)+zt1*d1*exp(-zi*dot_product(vkc(:,ik),tr(:)))
        endif
      enddo
    enddo !i
  endif
enddo !n
do n=1,nwann
  do j=1,nstsv
    if (abs(prjao(n,j)).lt.0.01) prjao(n,j)=zzero
  enddo
enddo

! compute ovelap matrix
allocate(s(nwann,nwann))
allocate(sdiag(nwann))
s=zzero
do m1=1,nwann
  do m2=1,nwann
    do j=1,nstsv
      s(m1,m2)=s(m1,m2)+prjao(m1,j)*dconjg(prjao(m2,j))
    enddo
  enddo
  sdiag(m1)=s(m1,m1)
enddo
! compute S^{-1/2}
call isqrtzhe(nwann,s,ierr)
if (ierr.ne.0) then
  write(*,*)
  write(*,'("Warning(genwann_c): failed to calculate S^{-1/2}")')
  write(*,'("  k-point : ",I4)')ik
  write(*,'("  iteration : ",I4)')iscl
  write(*,'("  number of linear dependent WFs : ",I4)')ierr
  write(*,'("  diagonal elements of overlap matrix : ")')
  write(*,'(6X,5G18.10)')abs(sdiag)
  write(*,'("Non-orthogonal WFs will be used")')
  write(*,*)
endif
! compute Wannier function expansion coefficients
wann_c_=zzero
if (ierr.eq.0) then
  do m1=1,nwann
    do m2=1,nwann
      wann_c_(m1,:)=wann_c_(m1,:)+prjao(m2,:)*dconjg(s(m2,m1))
    enddo
  enddo
else
  wann_c_=prjao
endif
deallocate(s,sdiag)
deallocate(prjao)
!if (ierr.ne.0) then
!  wann_nint_tmp(2,1)=wann_nint_tmp(2,1)+1
!  goto 10
!else
!  deallocate(wann_nint_tmp)
!endif
return
end
