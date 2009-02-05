
! Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.

!BOP
! !ROUTINE: bandstr
! !INTERFACE:
subroutine bandstr
! !USES:
use modmain
! !DESCRIPTION:
!   Produces a band structure along the path in reciprocal-space which connects
!   the vertices in the array {\tt vvlp1d}. The band structure is obtained from
!   the second-variational eigenvalues and is written to the file {\tt BAND.OUT}
!   with the Fermi energy set to zero. If required, band structures are plotted
!   to files {\tt BAND\_Sss\_Aaaaa.OUT} for atom {\tt aaaa} of species {\tt ss},
!   which include the band characters for each $l$ component of that atom in
!   columns 4 onwards. Column 3 contains the sum over $l$ of the characters.
!   Vertex location lines are written to {\tt BANDLINES.OUT}.
!
! !REVISION HISTORY:
!   Created June 2003 (JKD)
!EOP
!BOC
implicit none
! local variables
integer lmax,lmmax,l,m,lm
integer ik,ispn,is,ia,ias,iv,ist
real(8) emin,emax,sum
character(256) fname
! allocatable arrays
real(8), allocatable :: evalfv(:,:)
real(8), allocatable :: e(:,:)
! low precision for band character array saves memory
real(4), allocatable :: bc(:,:,:,:)
complex(8), allocatable :: dmat(:,:,:,:,:)
complex(8), allocatable :: apwalm(:,:,:,:,:)
complex(8), allocatable :: evecfv(:,:,:)
complex(8), allocatable :: evecsv(:,:)
integer, external :: ikglob
! initialise universal variables
call init0
call init1
! allocate array for storing the eigenvalues
allocate(e(nstsv,nkpt))
! maximum angular momentum for band character
lmax=min(3,lmaxapw)
lmmax=(lmax+1)**2
if (task.eq.21) then
  allocate(bc(0:lmax,natmtot,nstsv,nkpt))
  allocate(dmat(lmmax,lmmax,nspinor,nspinor,nstsv))
  allocate(apwalm(ngkmax,apwordmax,lmmaxapw,natmtot,nspnfv))
end if
allocate(evalfv(nstfv,nspnfv))
allocate(evecfv(nmatmax,nstfv,nspnfv))
allocate(evecsv(nstsv,nstsv))
! read density and potentials from file
call readstate
! read Fermi energy from file
call readfermi
! find the new linearisation energies
call linengy
! generate the APW radial functions
call genapwfr
! generate the local-orbital radial functions
call genlofr
! compute the overlap radial integrals
call olprad
! compute the Hamiltonian radial integrals
call hmlrad
! generate the local-orbital radial functions
call genlofr
call geturf
call genurfprod
emin=1.d5
emax=-1.d5
! begin parallel loop over k-points
e=0.d0
if (task.eq.21) bc=0.d0
do ik=1,nkptloc(iproc)
  write(*,'("Info(bandstr): ",I6," of ",I6," k-points")') ikglob(ik),nkpt
! solve the first- and second-variational secular equations
  call seceqn(ik,evalfv,evecfv,evecsv)
  do ist=1,nstsv
! subtract the Fermi energy
    e(ist,ikglob(ik))=evalsv(ist,ikglob(ik)) !-efermi
! add scissors correction
    if (e(ist,ikglob(ik)).gt.0.d0) e(ist,ikglob(ik))=e(ist,ikglob(ik))+scissor
  end do
! compute the band characters if required
  if (task.eq.21) then
! find the matching coefficients
    do ispn=1,nspnfv
      call match(ngk(ispn,ikglob(ik)),gkc(:,ispn,ik),tpgkc(:,:,ispn,ik), &
       sfacgk(:,:,ispn,ik),apwalm(:,:,:,:,ispn))
    end do
! average band character over spin and m for all atoms
    do is=1,nspecies
      do ia=1,natoms(is)
        ias=idxas(ia,is)
! generate the diagonal of the density matrix
        call gendmat(.true.,.true.,0,lmax,is,ia,ngk(:,ikglob(ik)),apwalm,evecfv, &
         evecsv,lmmax,dmat)
        do ist=1,nstsv
          do l=0,lmax
            sum=0.d0
            do m=-l,l
              lm=idxlm(l,m)
              do ispn=1,nspinor
                sum=sum+dble(dmat(lm,lm,ispn,ispn,ist))
              end do
            end do
            bc(l,ias,ist,ikglob(ik))=real(sum)
          end do
        end do
      end do
    end do
  end if
! end loop over k-points
end do
deallocate(evalfv,evecfv,evecsv) 
if (task.eq.21) then
  deallocate(dmat,apwalm)
endif
call dsync(e,nstsv*nkpt,.true.,.false.)
if (wannier) call dsync(wann_e,wann_nmax*wann_nspin*nkpt,.true.,.false.)
if (task.eq.21) then
  do ik=1,nkpt
    call rsync(bc(1,1,1,ik),(lmax+1)*natmtot*nstsv,.true.,.false.)
    call barrier
  enddo
endif 
emin=minval(e)
emax=maxval(e)
emax=emax+(emax-emin)*0.5d0
emin=emin-(emax-emin)*0.5d0
if (iproc.eq.0) then
! output the band structure
if (task.eq.20) then
  open(50,file='BAND.OUT',action='WRITE',form='FORMATTED')
  do ist=1,nstsv
    do ik=1,nkpt
      write(50,'(2G18.10)') dpp1d(ik),e(ist,ik)
    end do
    write(50,'("     ")')
  end do
  close(50)
  write(*,*)
  write(*,'("Info(bandstr):")')
  write(*,'(" band structure plot written to BAND.OUT")')
  if (wannier) then
    open(50,file='WANN_BAND.OUT',action='WRITE',form='FORMATTED')
    do ispn=1,wann_nspin
      write(50,'("# spin : ",I1)')ispn
      do ist=1,nwann(ispn)
        do ik=1,nkpt
          write(50,'(2G18.10)') dpp1d(ik),wann_e(ist,ispn,ik)
        end do
        write(50,'("     ")')
      end do
    enddo !ispn
  endif
else
  do is=1,nspecies
    do ia=1,natoms(is)
      ias=idxas(ia,is)
      write(fname,'("BAND_S",I2.2,"_A",I4.4,".OUT")') is,ia
      open(50,file=trim(fname),action='WRITE',form='FORMATTED')
      do ist=1,nstsv
        do ik=1,nkpt
! sum band character over l
          sum=0.d0
          do l=0,lmax
            sum=sum+bc(l,ias,ist,ik)
          end do
          write(50,'(2G18.10,8F12.6)') dpp1d(ik),e(ist,ik),sum, &
           (bc(l,ias,ist,ik),l=0,lmax)
        end do
        write(50,'("     ")')
      end do
      close(50)
    end do
  end do
  write(*,*)
  write(*,'("Info(bandstr):")')
  write(*,'(" band structure plot written to BAND_Sss_Aaaaa.OUT")')
  write(*,'("  for all species and atoms")')
end if
write(*,*)
write(*,'(" Fermi energy is at zero in plot")')
! output the vertex location lines
open(50,file='BANDLINES.OUT',action='WRITE',form='FORMATTED')
do iv=1,nvp1d
  write(50,'(2G18.10)') dvp1d(iv),emin
  write(50,'(2G18.10)') dvp1d(iv),emax
  write(50,'("     ")')
end do
close(50)
write(*,*)
write(*,'(" vertex location lines written to BANDLINES.OUT")')
write(*,*)
endif
deallocate(e)
if (task.eq.21) deallocate(bc)
return
end subroutine
!EOC
