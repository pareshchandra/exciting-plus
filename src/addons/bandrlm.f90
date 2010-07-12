
! Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.

!BOP
! !ROUTINE: bandstr
! !INTERFACE:
subroutine bandrlm
! !USES:
use modmain
use mod_mpi_grid
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
integer lmax,lmmax,lm,i,j,n
integer ik,ikloc,ispn,is,ia,ias,iv,ist
real(8) emin,emax
! allocatable arrays
real(8), allocatable :: evalfv(:,:)
! low precision for band character array saves memory
real(4), allocatable :: bc(:,:,:,:,:)
complex(8), allocatable :: evecfv(:,:,:)
complex(8), allocatable :: evecsv(:,:)
! initialise universal variables
call init0
call init1
! maximum angular momentum for band character
lmax=min(3,lmaxapw)
lmmax=(lmax+1)**2
allocate(bc(lmmax,natmtot,nspinor,nstsv,nkpt))
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
! generate muffin-tin effective magnetic fields and s.o. coupling functions
call genbeffmt
! get radial-muffint tin functions
call getufr
! get product of radial functions
call genufrp  
! begin parallel loop over k-points
if (sic) then
  if (allocated(evecsv0loc)) deallocate(evecsv0loc)
  allocate(evecsv0loc(nstsv,nstsv,nkptloc))
  call sic_readvwan
  call read_wann_ene
endif
bc=0.d0
evalsv=0.d0
evalsv0=0.d0
do ikloc=1,nkptloc
  ik=mpi_grid_map(nkpt,dim_k,loc=ikloc)
  write(*,'("Info(bandstr): ",I6," of ",I6," k-points")') ik,nkpt
! solve the first- and second-variational secular equations
  call seceqn(ikloc,evalfv,evecfv,evecsv)
  if (wannier) call genwann_h(ikloc)
! compute the band characters if required
  call bandchar(.true.,lmax,ikloc,evecfv,evecsv,lmmax,bc(1,1,1,1,ik))
! end loop over k-points
end do
deallocate(evalfv,evecfv,evecsv)
call mpi_grid_reduce(evalsv(1,1),nstsv*nkpt,dims=(/dim_k/),side=.true.)
if (wannier) call mpi_grid_reduce(wann_e(1,1),nwann*nkpt,dims=(/dim_k/),side=.true.)
do ik=1,nkpt
  call mpi_grid_reduce(bc(1,1,1,1,ik),lmmax*natmtot*nspinor*nstsv,dims=(/dim_k/),side=.true.)
enddo
emin=minval(evalsv)
emax=maxval(evalsv)
if (mpi_grid_root()) then
  open(50,file='BAND.OUT',action='WRITE',form='FORMATTED')
  do ist=1,nstsv
    do ik=1,nkpt
      write(50,'(2G18.10)') dpp1d(ik),evalsv(ist,ik)
    end do
    write(50,'("     ")')
  end do
  close(50)
  open(50,file='bands.dat',action='WRITE',form='FORMATTED')
  do ist=1,nstsv
    do ik=1,nkpt
      write(50,'(2G18.10)') dpp1d(ik),(evalsv(ist,ik)-efermi)*ha2ev
    end do
    write(50,'("     ")')
  end do
  close(50)
  write(*,*)
  write(*,'("Info(bandrlm):")')
  write(*,'(" band structure plot written to BAND.OUT")')
  if (wannier) then
    open(50,file='WANN_BAND.OUT',action='WRITE',form='FORMATTED')
    do ist=1,nwann
      do ik=1,nkpt
        write(50,'(2G18.10)') dpp1d(ik),wann_e(ist,ik)
      end do
      write(50,*)
    end do
    close(50)
    open(50,file='bands_wann.dat',action='WRITE',form='FORMATTED')
    do ist=1,nwann
      do ik=1,nkpt
        write(50,'(2G18.10)') dpp1d(ik),(wann_e(ist,ik)-efermi)*ha2ev
      end do
      write(50,*)
    end do
    close(50)
  endif
  open(50,file='BNDCHR.OUT',action='WRITE',form='FORMATTED')
  write(50,*)lmmax,nspecies,natmtot,nspinor,nstfv,nstsv,nkpt,nvp1d
  write(50,*)efermi
  do is=1,nspecies
    write(50,*)spsymb(is)
    write(50,*)natoms(is)
  enddo
  do is=1,nspecies
    do ia=1,natoms(is)
      write(50,*)idxas(ia,is),is
    enddo
  enddo  
  do ik=1,nkpt
    write(50,*)dpp1d(ik)
    write(50,*)(evalsv(ist,ik),ist=1,nstsv)
    write(50,*)((((bc(lm,ias,ispn,ist,ik),lm=1,lmmax), &
               ias=1,natmtot),ispn=1,nspinor),ist=1,nstsv)
  enddo
  write(50,*)wannier
  if (wannier) then
    write(50,*)nwann
  endif
endif

if (wannier) then
  if (mpi_grid_side(dims=(/dim_k/))) then
    do i=0,mpi_grid_size(dim_k)-1
      if (mpi_grid_x(dim_k).eq.i) then
        open(50,file='BNDCHR.OUT',form='FORMATTED',status='OLD',position='APPEND')
        do ikloc=1,nkptloc
          write(50,*)((abs(wann_c(n,j,ikloc)),n=1,nwann),j=1,nstfv)
        enddo
        close(50)
      endif
      call mpi_grid_barrier(dims=(/dim_k/))
    enddo
  endif
endif

if (mpi_grid_root()) then
! output the vertex location lines
  open(50,file='BANDLINES.OUT',action='WRITE',form='FORMATTED')
  do iv=1,nvp1d
    write(50,'(2G18.10)') dvp1d(iv),emin
    write(50,'(2G18.10)') dvp1d(iv),emax
    write(50,'("     ")')
  end do
  close(50)
  open(50,file='bandlines.dat',action='WRITE',form='FORMATTED')
  do iv=1,nvp1d
    write(50,'(2G18.10)') dvp1d(iv),(emin-efermi)*ha2ev
    write(50,'(2G18.10)') dvp1d(iv),(emax-efermi)*ha2ev
    write(50,'("     ")')
  end do
  write(50,'(2G18.10)') dvp1d(1),0.d0
  write(50,'(2G18.10)') dvp1d(nvp1d),0.d0
  close(50)
  write(*,*)
  write(*,'(" vertex location lines written to BANDLINES.OUT")')
  write(*,*)
endif
return
end subroutine
!EOC