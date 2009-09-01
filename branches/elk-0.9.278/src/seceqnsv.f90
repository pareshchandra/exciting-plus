
! Copyright (C) 2002-2007 J. K. Dewhurst, S. Sharma, C. Ambrosch-Draxl
! F. Bultmark, F. Cricchio and L. Nordstrom.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.

subroutine seceqnsv(ikloc,apwalm,evalfv,evecfv,evecsv)
use modmain
use modldapu
implicit none
! arguments
integer, intent(in) :: ikloc
complex(8), intent(in) :: apwalm(ngkmax,apwordmax,lmmaxapw,natmtot)
real(8), intent(in) :: evalfv(nstfv)
complex(8), intent(in) :: evecfv(nmatmax,nstfv)
complex(8), intent(out) :: evecsv(nstsv,nstsv)
! local variables
integer ispn,jspn,ia,is,ias,ik,ikloc1
integer ist,jst,i,j,k,l,lm,nm
integer nrc,irc,ir,igk,ifg
integer lmax,nsc,lwork,info
real(8) cb,t1
real(8) ts0,ts1
! automatic arrays
complex(8) zlflm(lmmaxvr,3)
! allocatable arrays
real(8), allocatable :: bir(:,:)
real(8), allocatable :: rwork(:)
complex(8), allocatable :: wfmt1(:,:,:)
complex(8), allocatable :: wfmt2(:,:)
complex(8), allocatable :: wfmt3(:,:)
complex(8), allocatable :: wfmt4(:,:,:)
complex(8), allocatable :: zfft1(:)
complex(8), allocatable :: zfft2(:)
complex(8), allocatable :: zv(:,:)
complex(8), allocatable :: work(:)
! external functions
complex(8) zdotc,zfmtinp
external zdotc,zfmtinp
ikloc1=ikloc
ik=cart_map(nkpt,dim_nkpt,loc=ikloc1)
! spin-unpolarised case
if ((.not.spinpol).and.(ldapu.eq.0)) then
  do i=1,nstsv
    evalsv(i,ik)=evalfv(i)
  end do
  evecsv(:,:)=0.d0
  do i=1,nstsv
    evecsv(i,i)=1.d0
  end do
  return
end if
call timesec(ts0)
! coupling constant of the external field (g_e/4c)
cb=gfacte/(4.d0*solsc)
! number of spin combinations after application of Hamiltonian
if (spinpol) then
  if (ncmag) then
    nsc=3
  else
    nsc=2
  end if
else
  nsc=1
end if
allocate(bir(ngrtot,3))
allocate(rwork(3*nstsv))
allocate(wfmt1(lmmaxvr,nrcmtmax,nstfv))
allocate(wfmt2(lmmaxvr,nrcmtmax))
allocate(wfmt3(lmmaxvr,nrcmtmax))
allocate(wfmt4(lmmaxvr,nrcmtmax,nsc))
allocate(zfft1(ngrtot))
allocate(zfft2(ngrtot))
allocate(zv(ngkmax,nsc))
lwork=2*nstsv
allocate(work(lwork))
lmax=min(lmaxmat,lmaxvr)
! zero the second-variational Hamiltonian (stored in the eigenvector array)
evecsv(:,:)=0.d0
!-------------------------!
!     muffin-tin part     !
!-------------------------!
do is=1,nspecies
  nrc=nrcmt(is)
  do ia=1,natoms(is)
    ias=idxas(ia,is)
! compute the first-variational wavefunctions
    do ist=1,nstfv
      call wavefmt(lradstp,lmaxvr,is,ia,ngk(1,ik),apwalm,evecfv(:,ist), &
       lmmaxvr,wfmt1(:,:,ist))
    end do
! begin loop over states
    do jst=1,nstfv
      if (spinpol) then
! convert wavefunction to spherical coordinates
        call zgemm('N','N',lmmaxvr,nrc,lmmaxvr,zone,zbshtvr,lmmaxvr, &
         wfmt1(:,:,jst),lmmaxvr,zzero,wfmt2,lmmaxvr)
! apply effective magnetic field and convert to spherical harmonics
        wfmt3(:,1:nrc)=wfmt2(:,1:nrc)*beffmt(:,1:nrc,ias,ndmag)
        call zgemm('N','N',lmmaxvr,nrc,lmmaxvr,zone,zfshtvr,lmmaxvr, &
         wfmt3,lmmaxvr,zzero,wfmt4(:,:,1),lmmaxvr)
        wfmt4(:,1:nrc,2)=-wfmt4(:,1:nrc,1)
! non-collinear field
        if (ncmag) then
          wfmt3(:,1:nrc)=wfmt2(:,1:nrc) &
           *cmplx(beffmt(:,1:nrc,ias,1),-beffmt(:,1:nrc,ias,2),8)
          call zgemm('N','N',lmmaxvr,nrc,lmmaxvr,zone,zfshtvr,lmmaxvr, &
           wfmt3,lmmaxvr,zzero,wfmt4(:,:,3),lmmaxvr)
        end if
! apply spin-orbit coupling if required
        if (spinorb) then
          do irc=1,nrc
            call lopzflm(lmaxvr,wfmt1(:,irc,jst),lmmaxvr,zlflm)
            t1=socfr(irc,ias)
            do lm=1,lmmaxvr
              wfmt4(lm,irc,1)=wfmt4(lm,irc,1)+t1*zlflm(lm,3)
              wfmt4(lm,irc,2)=wfmt4(lm,irc,2)-t1*zlflm(lm,3)
              wfmt4(lm,irc,3)=wfmt4(lm,irc,3)+t1*(zlflm(lm,1)-zi*zlflm(lm,2))
            end do
          end do
        end if
      else
        wfmt4(:,:,:)=0.d0
      end if
! apply LDA+U potential if required
      if ((ldapu.ne.0).and.(llu(is).ge.0)) then
        l=llu(is)
        nm=2*l+1
        lm=idxlm(l,-l)
        do k=1,nsc
          if (k.eq.1) then
            ispn=1
            jspn=1
          else if (k.eq.2) then
            ispn=2
            jspn=2
          else 
            ispn=1
            jspn=2
          end if
          call zgemm('N','N',nm,nrc,nm,zone,vmatlu(lm,lm,ispn,jspn,ias), &
           lmmaxlu,wfmt1(lm,1,jst),lmmaxvr,zone,wfmt4(lm,1,k),lmmaxvr)
        end do 
      end if
! second-variational Hamiltonian matrix
      do ist=1,nstfv
        do k=1,nsc
          if (k.eq.1) then
            i=ist
            j=jst
          else if (k.eq.2) then
            i=ist+nstfv
            j=jst+nstfv
          else
            i=ist
            j=jst+nstfv
          end if
          if (i.le.j) then
            evecsv(i,j)=evecsv(i,j)+zfmtinp(.true.,lmax,nrc,rcmt(:,is), &
             lmmaxvr,wfmt1(:,:,ist),wfmt4(:,:,k))
          end if
        end do
      end do
    end do
! end loops over atoms and species
  end do
end do
!---------------------------!
!     interstitial part     !
!---------------------------!
if (spinpol) then
  if (ncmag) then
! non-collinear
    do ir=1,ngrtot
      bir(ir,:)=(bxcir(ir,:)+cb*bfieldc(:))*cfunir(ir)
    end do
  else
! collinear
    do ir=1,ngrtot
      bir(ir,1:2)=0.d0
      bir(ir,3)=(bxcir(ir,1)+cb*bfieldc(3))*cfunir(ir)
    end do
  end if
  do jst=1,nstfv
    zfft1(:)=0.d0
    do igk=1,ngk(1,ik)
      ifg=igfft(igkig(igk,1,ikloc))
      zfft1(ifg)=evecfv(igk,jst)
    end do
! Fourier transform wavefunction to real-space
    call zfftifc(3,ngrid,1,zfft1)
! multiply with magnetic field and transform to G-space
    zfft2(:)=zfft1(:)*bir(:,3)
    call zfftifc(3,ngrid,-1,zfft2)
    do igk=1,ngk(1,ik)
      ifg=igfft(igkig(igk,1,ikloc))
      zv(igk,1)=zfft2(ifg)
      zv(igk,2)=-zfft2(ifg)
    end do
    if (ncmag) then
      zfft2(:)=zfft1(:)*cmplx(bir(:,1),-bir(:,2),8)
      call zfftifc(3,ngrid,-1,zfft2)
      do igk=1,ngk(1,ik)
        ifg=igfft(igkig(igk,1,ikloc))
        zv(igk,3)=zfft2(ifg)
      end do
    end if
! add to Hamiltonian matrix
    do ist=1,nstfv
      do k=1,nsc
        if (k.eq.1) then
          i=ist
          j=jst
        else if (k.eq.2) then
          i=ist+nstfv
          j=jst+nstfv
        else
          i=ist
          j=jst+nstfv
        end if
        if (i.le.j) then
          evecsv(i,j)=evecsv(i,j)+zdotc(ngk(1,ik),evecfv(:,ist),1,zv(:,k),1)
        end if
      end do
    end do
  end do
end if
! add the diagonal first-variational part
i=0
do ispn=1,nspinor
  do ist=1,nstfv
    i=i+1
    evecsv(i,i)=evecsv(i,i)+evalfv(ist)
  end do
end do
! diagonalise second-variational Hamiltonian
if (ndmag.eq.1) then
! collinear: block diagonalise H
  call zheev('V','U',nstfv,evecsv,nstsv,evalsv(:,ik),work,lwork,rwork,info)
  if (info.ne.0) goto 20
  i=nstfv+1
  call zheev('V','U',nstfv,evecsv(i,i),nstsv,evalsv(i,ik),work,lwork,rwork,info)
  if (info.ne.0) goto 20
  do i=1,nstfv
    do j=1,nstfv
      evecsv(i,j+nstfv)=0.d0
      evecsv(i+nstfv,j)=0.d0
    end do
  end do
else
! non-collinear or spin-unpolarised: full diagonalisation
  call zheev('V','U',nstsv,evecsv,nstsv,evalsv(:,ik),work,lwork,rwork,info)
  if (info.ne.0) goto 20
end if
deallocate(bir,rwork,wfmt1,wfmt2,wfmt3,wfmt4)
deallocate(zfft1,zfft2,zv,work)
call timesec(ts1)
timesv=timesv+ts1-ts0
return
20 continue
write(*,*)
write(*,'("Error(seceqnsv): diagonalisation of the second-variational &
 &Hamiltonian failed")')
write(*,'(" for k-point ",I8)') ik
write(*,'(" ZHEEV returned INFO = ",I8)') info
write(*,*)
stop
end subroutine
