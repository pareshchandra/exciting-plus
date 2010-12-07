subroutine sic_main
use modmain
use mod_nrkp
use mod_hdf5
use mod_sic
use mod_wannier
use mod_linresp
implicit none
integer n,sz,i,j,i1,j1,j2,n1,n2,ik,ispn,vtrl(3)
real(8) t1,t2,t3,vtrc(3)
integer vl(3)
! Wannier functions
complex(8), allocatable :: vwanme_old(:)
complex(8), allocatable :: ene(:,:)
complex(8), allocatable :: vwank(:,:)
complex(8) z1

sic=.true.

! initialise universal variables
call init0
call init1
if (.not.mpi_grid_in()) return
! read the density and potentials from file
call readstate
! find the new linearisation energies
call linengy
! generate the APW radial functions
call genapwfr
! generate the local-orbital radial functions
call genlofr
call getufr
call genufrp

wproc=mpi_grid_root()
if (wproc) then
  open(151,file="SIC.OUT",form="FORMATTED",status="REPLACE")
endif
if (wproc) then
  sz=lmmaxvr*nmtloc+ngrloc
  sz=16.d0*sz*ntr*nspinor*(nwantot+sic_wantran%nwan)/1024/1024
  write(151,*)
  write(151,'("Required memory for real-space arrays (MB) : ",I6)')sz
  write(151,*)
  write(151,'("cutoff radius for Wannier functions : ",F12.6)')sic_wan_cutoff
  write(151,'("cutoff radius for SIC matrix elements : ",F12.6)')sic_me_cutoff
  write(151,*)
  write(151,'("number of translations : ",I4)')ntr
  do i=1,ntr
    write(151,'("  i : ",I4,"    vtl(i) : ",3I4)')i,vtl(:,i)
  enddo
  write(151,*)
  write(151,'("number of included Wannier functions : ",I4)')sic_wantran%nwan
  do j=1,sic_wantran%nwan
    write(151,'("  j : ",I4,"    iwan(j) : ",I4)')j,sic_wantran%iwan(j)
  enddo
  call flushifc(151)
endif
! generate wave-functions for all k-points in BZ
call genwfnr(151,.false.)  
call sic_wan(151)
allocate(ene(4,sic_wantran%nwan))
call sic_pot(151,ene)
! save old matrix elements
allocate(vwanme_old(sic_wantran%nwt))
vwanme_old=vwanme
! compute matrix elements of SIC potential
!  vwanme = <w_n|v_n|w_{n1,T}>
vwanme=zzero
do i=1,sic_wantran%nwt
  n=sic_wantran%iwt(1,i)
  j=sic_wantran%idxiwan(n)
  n1=sic_wantran%iwt(2,i)
  vl(:)=sic_wantran%iwt(3:5,i)
  do ispn=1,nspinor    
    vwanme(i)=vwanme(i)+sic_dot_ll(wvmt(1,1,1,ispn,j),wvir(1,1,ispn,j),&
      wanmt(1,1,1,ispn,n1),wanir(1,1,ispn,n1),vl,twanmt(1,1,n),twanmt(1,1,n1))
  enddo
enddo
t1=0.d0
t2=-1.d0
t3=0.d0
do i=1,sic_wantran%nwt
  n=sic_wantran%iwt(1,i)
  n1=sic_wantran%iwt(2,i)
  vl(:)=sic_wantran%iwt(3:5,i)
  j=sic_wantran%iwtidx(n1,n,-vl(1),-vl(2),-vl(3))
  t1=t1+abs(vwanme(i)-dconjg(vwanme(j)))
  if (abs(vwanme(i)-dconjg(vwanme(j))).ge.t2) then
    t2=abs(vwanme(i)-dconjg(vwanme(j)))
    i1=i
    j1=j
  endif
  t3=t3+abs(vwanme(i)-vwanme_old(i))**2
enddo
if (wproc) then
  call timestamp(151,"done with matrix elements")
  write(151,*)
  write(151,'("Number of Wannier transitions : ",I6)')sic_wantran%nwt
!  write(151,'("Matrix elements of SIC potential (n n1  <w_n|v_n|w_n1}>)")')
!  do i=1,sic_wantran%nwt
!    vl(:)=sic_wantran%iwt(3:5,i)
!    if (all(vl.eq.0)) then
!      write(151,'(I4,4X,I4,4X,2G18.10)')sic_wantran%iwt(1:2,i),&
!        dreal(vwanme(i)),dimag(vwanme(i))
!    endif
!  enddo
  write(151,*)
  write(151,'("Maximum deviation from ""localization criterion"" : ",F12.6)')t2
!  write(151,'("Average deviation from ""localization criterion"" : ",F12.6)')&
!    t1/sic_wantran%nwt
!  write(151,*)
  write(151,'("Matrix elements with maximum difference : ",2I6)')i1,j1
  write(151,'(I4,4X,I4,4X,3I4,4X,2G18.10)')sic_wantran%iwt(:,i1),&
        dreal(vwanme(i1)),dimag(vwanme(i1))
  write(151,'(I4,4X,I4,4X,3I4,4X,2G18.10)')sic_wantran%iwt(:,j1),&
        dreal(vwanme(j1)),dimag(vwanme(j1))
  write(151,*)
  write(151,'("Diagonal matrix elements")')
  write(151,'(2X,"wann",18X,"V_n")')
  write(151,'(44("-"))')
  do j=1,sic_wantran%nwan
    n=sic_wantran%iwan(j)
    i=sic_wantran%iwtidx(n,n,0,0,0)
    write(151,'(I4,4X,2G18.10)')n,dreal(vwanme(i)),dimag(vwanme(i))
  enddo  
  t3=sqrt(t3/sic_wantran%nwt)
  write(151,*)
  write(151,'("SIC matrix elements RMS difference :",G18.10)')t3  
  call flushifc(151)
endif
deallocate(vwanme_old)
! check hermiticity of V_nn'(k)
allocate(vwank(sic_wantran%nwan,sic_wantran%nwan))
do ik=1,nkpt
  vwank=zzero
  do i=1,sic_wantran%nwt
    n1=sic_wantran%iwt(1,i)
    j1=sic_wantran%idxiwan(n1)
    n2=sic_wantran%iwt(2,i)
    j2=sic_wantran%idxiwan(n2)
    vtrl(:)=sic_wantran%iwt(3:5,i)
    vtrc(:)=vtrl(1)*avec(:,1)+vtrl(2)*avec(:,2)+vtrl(3)*avec(:,3)
    z1=exp(zi*dot_product(vkc(:,ik),vtrc(:)))
    vwank(j1,j2)=vwank(j1,j2)+z1*vwanme(i)
  enddo
  t1=0.d0
  do j1=1,sic_wantran%nwan
    do j2=1,sic_wantran%nwan
      t1=max(t1,abs(vwank(j1,j2)-dconjg(vwank(j2,j1))))
    enddo
  enddo
  if (wproc) then
    write(151,'("ik : ",I4,"   max.herm.err : ",G18.10 )')ik,t1
  endif
enddo
deallocate(vwank)
if (wproc) close(151)
! signal that now we have computed sic potential and wannier functions
tsic_wv=.true.
! write to HDF5 file after last iteration
if (isclsic.eq.nsclsic) call sic_writevwan
deallocate(ene)
return
end