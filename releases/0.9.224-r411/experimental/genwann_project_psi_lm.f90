subroutine genwann(ik,evecfv,evecsv)
use modmain
implicit none
! arguments
integer, intent(in) :: ik
complex(8), intent(in) :: evecfv(nmatmax,nstfv)
complex(8), intent(in) :: evecsv(nstsv,nstsv)

complex(8), allocatable :: apwalm(:,:,:,:)
complex(8), allocatable :: wfsvmt(:,:,:,:,:)
complex(8), allocatable :: wfsvit(:,:,:)
integer ispn,i,j,n,m1,m2
complex(8), allocatable :: zt2(:,:)
integer, external :: ikglob
! allocate arrays
allocate(wfsvmt(lmmaxvr,nrfmax,natmtot,nstsv,nspinor))
allocate(wfsvit(ngkmax,nstsv,nspinor))
allocate(apwalm(ngkmax,apwordmax,lmmaxapw,natmtot))
call match(ngk(1,ikglob(ik)),gkc(1,1,ik),tpgkc(1,1,1,ik),sfacgk(1,1,1,ik),apwalm)
! generate second-varioational wave-functions
call genwfsvmt(lmaxvr,lmmaxvr,ngk(1,ikglob(ik)),evecfv,evecsv,apwalm,wfsvmt)
call genwfsvit(ngk(1,ikglob(ik)),evecfv,evecsv,wfsvit)
! calculate WF expansion coefficients
call genwann_c(evalsv(1,ikglob(ik)),wfsvmt,wann_c(1,1,1,ik))
! compute H(k) in WF basis
do ispn=1,wann_nspin
  allocate(zt2(nwann(ispn),nwann(ispn)))
  zt2=dcmplx(0.d0,0.d0)
  do m1=1,nwann(ispn)
    do m2=1,nwann(ispn)
      do j=1,nstfv
        zt2(m1,m2)=zt2(m1,m2)+dconjg(wann_c(m1,j,ispn,ik))*wann_c(m2,j,ispn,ik) * &
	      evalsv(j+(ispn-1)*nstfv,ikglob(ik))
      enddo
    enddo
  enddo
  wann_h(1:nwann(ispn),1:nwann(ispn),ispn,ikglob(ik))=zt2(:,:)
  call diagzhe(nwann(ispn),zt2,wann_e(1,ispn,ikglob(ik)))
  deallocate(zt2)
enddo !ispn
! compute Bloch-sums of Wannier functions
wann_unkmt(:,:,:,:,:,ik)=dcmplx(0.d0,0.d0)
wann_unkit(:,:,:,ik)=dcmplx(0.d0,0.d0)
do ispn=1,wann_nspin
  do n=1,nwann(ispn)
    do i=1,nstfv
      wann_unkmt(:,:,:,n,ispn,ik)=wann_unkmt(:,:,:,n,ispn,ik) + &
        wfsvmt(:,:,:,i+(ispn-1)*nstfv,ispn)*wann_c(n,i,ispn,ik)
      wann_unkit(:,n,ispn,ik)=wann_unkit(:,n,ispn,ik) + &
        wfsvit(:,i+(ispn-1)*nstfv,1)*wann_c(n,i,ispn,ik)
    enddo
  enddo
enddo

deallocate(wfsvmt,wfsvit,apwalm)

return
end

subroutine genwann_c(e,wfsvmt,wf)
use modmain
implicit none
! arguments
real(8), intent(in) :: e(nstsv)
complex(8), intent(in) :: wfsvmt(lmmaxvr,nrfmax,natmtot,nstsv,nspinor)
complex(8), intent(out) :: wf(wann_nmax,nstfv,wann_nspin)

complex(8), allocatable :: prjao(:,:,:)
complex(8), allocatable :: s(:,:)
integer ispn,i,j,n,m1,m2,io1,io2,ias,lm,lm1,lm2,ierr,l,itype
integer n1n2(2,2,wann_ntype),n1,n2
complex(8), allocatable :: dm1(:,:)

n1n2=0
! find bands for a given energy interval 
if (wann_use_eint) then
  do ispn=1,wann_nspin
    do j=1,wann_ntype
      n1n2(1,ispn,j)=1
      do i=1,nstfv
        if (e(i+(ispn-1)*nstfv).lt.wann_eint(1,j)) n1n2(1,ispn,j)=i+1
        if (e(i+(ispn-1)*nstfv).le.wann_eint(2,j)) n1n2(2,ispn,j)=i
      enddo
    enddo    
  enddo
endif

! compute <\psi|g_n>
allocate(prjao(wann_nmax,nstfv,wann_nspin))
prjao=dcmplx(0.d0,0.d0)
do ispn=1,wann_nspin
  do n=1,nwann(ispn)
    ias=iwann(n,ispn,1)
    lm=iwann(n,ispn,2)
    l=iwann(n,ispn,3)    
    itype=iwann(n,ispn,4)
    if (wann_use_eint) then
      n1=n1n2(1,ispn,itype)
      n2=n1n2(2,ispn,itype)
    else
      n1=wann_nint(1,itype)
      n2=wann_nint(2,itype)
    endif
    allocate(dm1(2*l+1,2*l+1))
    do j=n1,n2
      dm1=dcmplx(0.d0,0.d0)
      do m1=-l,l
      do m2=-l,l
        do io1=1,nrfmax
        do io2=1,nrfmax
          dm1(m1+l+1,m2+l+1)=dm1(m1+l+1,m2+l+1)+&
            dconjg(wfsvmt(idxlm(l,m1),io1,ias,j+(ispn-1)*nstsv,ispn))*&
            wfsvmt(idxlm(l,m2),io2,ias,j+(ispn-1)*nstsv,ispn)*urfprod(l,io1,io2,ias)
        enddo
        enddo
      enddo
      enddo
      do m1=-l,l
      do m2=-l,l
        prjao(n,j,ispn)=prjao(n,j,ispn)+dconjg(yrlm_lcs(idxlm(l,m1),lm,ias))*yrlm_lcs(idxlm(l,m2),lm,ias)*dm1(m1+l+1,m2+l+1)
      enddo
      enddo
      write(*,*)'prjao=',prjao(n,j,ispn)
    enddo !j
    deallocate(dm1)
  enddo !n
enddo !ispn


do ispn=1,wann_nspin
  allocate(s(nwann(ispn),nwann(ispn)))
! compute ovelap matrix
  s=dcmplx(0.d0,0.d0)
  do m1=1,nwann(ispn)
    do m2=1,nwann(ispn)
      do j=1,nstfv
        s(m1,m2)=s(m1,m2)+prjao(m1,j,ispn)*dconjg(prjao(m2,j,ispn))
      enddo
    enddo
  enddo
! compute S^{-1/2}
  call isqrtzhe(nwann(ispn),s,ierr)
  if (ierr.ne.0) then
    write(*,*)
    write(*,'("Error(genwann2): failed to calculate S^{-1/2} for spin ",I1)')ispn
    write(*,'("  ierr : ",I4)')ierr
    do n=1,nwann(ispn)
      itype=iwann(n,ispn,4)
      write(*,*)
      write(*,'(" n : ",I4,"  type : ",I4,"  N1,N2 : ",2I4)')n,itype,n1,n2
      write(*,'("   |<\psi_i|\phi_n>| : ")')
      write(*,'(6X,10G18.10)')abs(prjao(n,:,ispn))
      write(*,'("   sum(abs(|..|)) : ",G18.10)')sum(abs(prjao(n,:,ispn)))
    enddo
    write(*,*)
  endif
! compute Wannier function expansion coefficients
  wf(:,:,ispn)=dcmplx(0.d0,0.d0)
  if (ierr.eq.0) then
    do m1=1,nwann(ispn)
      do m2=1,nwann(ispn)
        wf(m1,:,ispn)=wf(m1,:,ispn)+prjao(m2,:,ispn)*dconjg(s(m2,m1))
      enddo
    enddo
  else
    wf(:,:,ispn)=prjao(:,:,ispn)
  endif
  deallocate(s)
enddo !ispn

deallocate(prjao)

return
end