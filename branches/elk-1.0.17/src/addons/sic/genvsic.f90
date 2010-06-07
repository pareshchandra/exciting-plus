subroutine genvsic
use modmain
use mod_lf
use mod_nrkp
use modxcifc
use mod_addons_q
use mod_hdf5
implicit none

integer n
integer ik,ikloc,j,sz,i,itp
integer n1,n2,ispn
integer itr,it,itloc,ir,m,ias
real(8) t1,t2
integer v1l(3),lm1,lm2,lm3
character*12 c1,c2,c3
character*100 path
integer ntp
real(8), allocatable :: tp(:,:)
complex(8), allocatable :: ylm(:,:)
complex(8) zt1
real(8), external :: gaunt

! arrays for Wannier functions
complex(8), allocatable :: wanmt0(:,:,:,:,:)
complex(8), allocatable :: wanir0(:,:,:)

real(8), allocatable :: rhowanir(:)
!complex(8), allocatable :: f1mt(:,:,:)
complex(8), allocatable :: f1mt(:,:)
complex(8), allocatable :: f2mt(:,:)
complex(8), allocatable :: f3mt(:,:)

complex(8), allocatable :: vsic(:)
complex(8), allocatable :: h0wan(:),zm1(:,:,:)
real(8), allocatable :: f3(:),f4(:),f5(:)

integer lm
real(8), allocatable :: vx(:),vc(:)
complex(8) z1,expikt
real(8) vtrc(3)

! mpi grid layout
!          (2)
!     +----+----+--> T-vectos 
!     |    |    |
!     +----+----+--
! (1) |    |    |
!     +----+----+--
!     |    |    |
!     v
!  k-points


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
! read Fermi energy
if (mpi_grid_root()) call readfermi
call mpi_grid_bcast(efermi)

call lf_init(lf_maxt,dim2)
wproc=mpi_grid_root()
if (wproc) then
  open(151,file='SIC.OUT',form='FORMATTED',status='REPLACE')
endif
call genwfnr(151,.false.)  
if (wproc) then
  call timestamp(151,'done with wavefunctions')
  call flushifc(151)
endif
! get all Wannier transitions
all_wan_ibt=.true.
call getimegqwan(all_wan_ibt)
! compute Fourier transform of <n,T=0|H^{LDA}|n',T'>
allocate(zm1(nwann,nwann,nkptnrloc))
zm1=zzero
do ikloc=1,nkptnrloc
  ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
  do n1=1,nwann
    do n2=1,nwann
      do j=1,nstsv
        zm1(n1,n2,ikloc)=zm1(n1,n2,ikloc)+dconjg(wann_c(n1,j,ikloc))*&
          wann_c(n2,j,ikloc)*evalsvnr(j,ik)
      enddo
    enddo
  enddo
enddo 
! compute <n,T=0|H^{LDA}|n',T'>
allocate(h0wan(nmegqwan))
h0wan=zzero
do i=1,nmegqwan
  n=imegqwan(1,i)
  n1=imegqwan(2,i)
  v1l(:)=imegqwan(3:5,i)
  vtrc(:)=v1l(1)*avec(:,1)+v1l(2)*avec(:,2)+v1l(3)*avec(:,3)
  do ikloc=1,nkptnrloc
    ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
    expikt=exp(-1.d0*zi*dot_product(vkcnr(:,ik),vtrc(:)))
    h0wan(i)=h0wan(i)+expikt*zm1(n,n1,ikloc)
  enddo
enddo
call mpi_grid_reduce(h0wan(1),nmegqwan,dims=(/dim_k/))
h0wan(:)=h0wan(:)/nkptnr
deallocate(zm1)


if (allocated(vwanmt)) deallocate(vwanmt)
allocate(vwanmt(lmmaxvr,nrmtmax,natmtot,ntrloc,nspinor,nwann))
if (allocated(vwanir)) deallocate(vwanir)
allocate(vwanir(ngrtot,ntrloc,nspinor,nwann))
vwanmt=zzero
vwanir=zzero

call genvhwan

! restore wproc
wproc=mpi_grid_root()
if (wproc) then
  write(151,*)
  write(151,'("time for q-vectors : ",F8.3)')timer_get_value(10)
  write(151,'("time for Hartree potential : ",F8.3)')timer_get_value(11)
endif

! deallocate unnecessary arrays
deallocate(wfsvmtloc)
deallocate(wfsvitloc)
deallocate(evecfvloc)
deallocate(evecsvloc)
deallocate(wann_c)

! generate Wannier functions on a mesh
if (allocated(wanmt)) deallocate(wanmt)
allocate(wanmt(lmmaxvr,nrmtmax,natmtot,ntrloc,nspinor,nwann))
if (allocated(wanir)) deallocate(wanir)
allocate(wanir(ngrtot,ntrloc,nspinor,nwann))
if (wproc) then
  sz=lmmaxvr*nrmtmax*natmtot+ngrtot
  sz=16*sz*nspinor*nwann*ntrloc/1024/1024
  write(151,*)
  write(151,'("Size of real-space Wannier functions arrays (MB) : ",I6)')sz
  write(151,*)
  call flushifc(151)
endif
call timer_reset(1)
call timer_reset(2)
allocate(wanmt0(lmmaxvr,nrmtmax,natmtot,nspinor,nwann))
allocate(wanir0(ngrtot,nspinor,nwann))
do itloc=1,ntrloc
  itr=mpi_grid_map(ntr,dim_t,loc=itloc)
  call gen_wann_func(vtl(1,itr),ngknr,vgkcnr,igkignr,wanmt0,wanir0)
  do ispn=1,nspinor
    do n=1,nwann
      wanmt(:,:,:,itloc,ispn,n)=wanmt0(:,:,:,ispn,n)
      wanir(:,itloc,ispn,n)=wanir0(:,ispn,n)
    enddo !n
  enddo !ispn
enddo !itr
deallocate(wanmt0,wanir0)
if (wproc) then
  write(151,*)
  write(151,'("MT part : ",F8.3)')timer_get_value(1)
  write(151,'("IT part : ",F8.3)')timer_get_value(2)
  call flushifc(151)
endif
if (wproc) then
  call timestamp(151,'done with Wannier functions')
endif

call timer_start(12,reset=.true.)
ntp=1000
allocate(tp(2,ntp))
allocate(ylm(lmmaxvr,ntp))
call sphcover(ntp,tp)
do itp=1,ntp 
  call genylm(lmaxvr,tp(1,itp),ylm(1,itp))
enddo
m=max(ntp,ngrtot)
allocate(rhowanir(ngrtot))
allocate(f3(m),f4(m),f5(m))
allocate(vx(m),vc(m))
! add XC potential to Coulomb
do n=1,nwann
  do itloc=1,ntrloc
! muffin-tin part
    do ias=1,natmtot
      do ir=1,nrmt(ias2is(ias))
! compute charge density on a sphere
        f5=0.d0
        do itp=1,ntp
          do ispn=1,nspinor
            zt1=zzero            
            do lm=1,lmmaxvr
              zt1=zt1+wanmt(lm,ir,ias,itloc,ispn,n)*ylm(lm,itp)
            enddo
            f5(itp)=f5(itp)+abs(zt1)**2
          enddo
        enddo !itp
        call xcifc(xctype,n=ntp,rho=f5,ex=f3,ec=f4,vx=vx,vc=vc)
! save XC potential
        f5(1:ntp)=vx(1:ntp)+vc(1:ntp)
! expand XC potential in spherical harmonics
        do lm=1,lmmaxvr
          zt1=zzero
          do itp=1,ntp
            zt1=zt1+dconjg(ylm(lm,itp))*f5(itp)
          enddo
          vwanmt(lm,ir,ias,itloc,1,n)=vwanmt(lm,ir,ias,itloc,1,n)+&
            fourpi*zt1/ntp
        enddo
      enddo
    enddo  
    rhowanir(:)=dreal(dconjg(wanir(:,itloc,1,n))*wanir(:,itloc,1,n))
    if (spinpol) then
      rhowanir(:)=rhowanir(:)+&
        dreal(dconjg(wanir(:,itloc,2,n))*wanir(:,itloc,2,n))
    endif
    call xcifc(xctype,n=ngrtot,rho=rhowanir(:),ex=f3,ec=f4,vx=vx,vc=vc)
    vwanir(:,itloc,1,n)=vwanir(:,itloc,1,n)+vc(1:ngrtot)+vx(1:ngrtot)
  enddo
enddo
deallocate(vx,vc,f3,f4,rhowanir)
call timer_stop(12)
if (wproc) then
  write(151,'("time for XC potential : ",F8.3)')timer_get_value(12)
endif

if (spinpol) then
  do n=1,nwann
    vwanmt(:,:,:,:,2,n)=vwanmt(:,:,:,:,1,n)
    vwanir(:,:,2,n)=vwanir(:,:,1,n)
  enddo
endif
call timer_start(13,reset=.true.)
! multiply potential by Wannier function and change sign
allocate(f1mt(nrmtmax,lmmaxvr))
allocate(f2mt(nrmtmax,lmmaxvr))
allocate(f3mt(nrmtmax,lmmaxvr))
do n=1,nwann
  do itloc=1,ntrloc
    do ispn=1,nspinor     
      do ias=1,natmtot
        f3mt=zzero
        do lm1=1,lmmaxvr
          f1mt(:,lm1)=vwanmt(lm1,:,ias,itloc,ispn,n)
          f2mt(:,lm1)=wanmt(lm1,:,ias,itloc,ispn,n)
        enddo
        do lm1=1,lmmaxvr
          do lm2=1,lmmaxvr
            do lm3=1,lmmaxvr
              t1=gaunt(lm2l(lm3),lm2l(lm1),lm2l(lm2),&
                       lm2m(lm3),lm2m(lm1),lm2m(lm2))
              if (abs(t1).gt.1d-8) then
                do ir=1,nrmt(ias2is(ias))
                  f3mt(ir,lm3)=f3mt(ir,lm3)+f1mt(ir,lm1)*f2mt(ir,lm2)*t1
                enddo
              endif
            enddo
          enddo
        enddo
        do lm3=1,lmmaxvr
          vwanmt(lm3,:,ias,itloc,ispn,n)=-f3mt(:,lm3)
        enddo
      enddo !ias
      vwanir(:,itloc,ispn,n)=-vwanir(:,itloc,ispn,n)*wanir(:,itloc,ispn,n)
    enddo !ispn
  enddo !itloc
enddo !n
deallocate(f1mt,f2mt,f3mt)
call timer_stop(13)
if (wproc) then
  write(151,'("time for V*WF product : ",F8.3)')timer_get_value(13)
endif

! convert to spherical harmonics
!do n=1,nwann
!  do itloc=1,ntrloc
!    do ispn=1,nspinor
!      call lf_sht('F',vwanmt(1,1,1,itloc,ispn,n),vwanmt(1,1,1,itloc,ispn,n))
!      call lf_sht('F',wanmt(1,1,1,itloc,ispn,n),wanmt(1,1,1,itloc,ispn,n))
!    enddo
!  enddo
!enddo

! check orthonormality
t1=0.d0
t2=0.d0
do i=1,nmegqwan
  n=imegqwan(1,i)
  n1=imegqwan(2,i)
  v1l(:)=imegqwan(3:5,i)
  z1=0
  do ispn=1,nspinor
    z1=z1+lf_dotlf(.true.,v1l,wanmt(1,1,1,1,ispn,n),wanir(1,1,ispn,n),&
      wanmt(1,1,1,1,ispn,n1),wanir(1,1,ispn,n1))
  enddo
  if (n.eq.n1.and.v1l(1).eq.0.and.v1l(2).eq.0.and.v1l(3).eq.0) then
    z1=z1-zone
  endif
  t2=max(t2,abs(z1))
  t1=t1+abs(z1)
enddo
if (wproc) then
  write(151,*)
  write(151,'("Maximum deviation from norm : ",F12.6)')t2
  write(151,'("Average deviation from norm : ",F12.6)')t1/nmegqwan
  call flushifc(151)
endif

allocate(vsic(nmegqwan))
vsic=zzero
! compute matrix elements of SIC potential
! vsic = <w_n|v_n|w_{n1,T}>
do i=1,nmegqwan
  n=imegqwan(1,i)
  n1=imegqwan(2,i)
  v1l(:)=imegqwan(3:5,i)
  do ispn=1,nspinor
    vsic(i)=vsic(i)+lf_dotlf(.true.,v1l,vwanmt(1,1,1,1,ispn,n),&
      vwanir(1,1,ispn,n),wanmt(1,1,1,1,ispn,n1),wanir(1,1,ispn,n1))
  enddo
enddo
if (wproc) then
  call timestamp(151,'done with matrix elements')
endif
if (wproc) then
  write(151,*)
  write(151,'("Number of Wannier transitions : ",I6)')nmegqwan
  write(151,'("Matrix elements of SIC potential &
    &(n n1  T  <w_n|v_n|w_{n1,T}>)")')
  do i=1,nmegqwan
    write(151,'(I4,4X,I4,4X,3I3,4X,2G18.10)')imegqwan(:,i),&
      dreal(vsic(i)),dimag(vsic(i))
  enddo
endif

t2=0.d0
do i=1,nmegqwan
  n=imegqwan(1,i)
  n1=imegqwan(2,i)
  v1l(:)=imegqwan(3:5,i)
  j=idxmegqwan(n1,n,-v1l(1),-v1l(2),-v1l(3))
  t2=max(t2,abs(vsic(i)-dconjg(vsic(j))))
enddo
if (wproc) then
  write(151,*)
  write(151,'("Maximum deviation from ""localization criterion"" : ",F12.6)')t2
  write(151,*)
  write(151,'("Diagonal matrix elements")')
  write(151,'("   n    Re H_nn     Im H_nn     Re V_n      Im V_n")')
  write(151,'(70("-"))')
  do n=1,nwann
    j=idxmegqwan(n,n,0,0,0)
    write(151,'(I4,4F12.6)')n,dreal(h0wan(j)),dimag(h0wan(j)),&
      dreal(vsic(j)),dimag(vsic(j))
  enddo  
  call flushifc(151)
endif
if (wproc) then
  call hdf5_create_file("sic.hdf5")
  call hdf5_create_group("sic.hdf5","/","wann")
  do n=1,nwann
    path="/wann"
    write(c1,'("n",I4.4)')n
    call hdf5_create_group("sic.hdf5",path,trim(adjustl(c1)))   
    path=trim(path)//"/"//trim(adjustl(c1))
    do ispn=1,nspinor
      write(c3,'("s",I4.4)')ispn
      call hdf5_create_group("sic.hdf5",path,trim(adjustl(c3)))   
      path=trim(path)//"/"//trim(adjustl(c3))      
      do it=1,ntr
        write(c2,'("t",I4.4)')it
        call hdf5_create_group("sic.hdf5",path,trim(adjustl(c2)))
      enddo
    enddo
  enddo
  call hdf5_write("sic.hdf5","/","nmegqwan",nmegqwan)
  call hdf5_write("sic.hdf5","/","imegqwan",imegqwan(1,1),(/5,nmegqwan/))
  call hdf5_write("sic.hdf5","/","vsic",vsic(1),(/nmegqwan/))
  call hdf5_write("sic.hdf5","/","h0wan",h0wan(1),(/nmegqwan/))
endif
if (mpi_grid_side(dims=(/dim_t/))) then
  do i=0,mpi_grid_size(dim_t)-1
    if (mpi_grid_x(dim_t).eq.i) then
      do itloc=1,ntrloc
        itr=mpi_grid_map(ntr,dim_t,loc=itloc)
        do ispn=1,nspinor
          do n=1,nwann
            write(c1,'("n",I4.4)')n
            write(c2,'("t",I4.4)')itr
            write(c3,'("s",I4.4)')ispn
            path="/wann/"//trim(adjustl(c1))//"/"//trim(adjustl(c3))//"/"//&
              trim(adjustl(c2))
            call hdf5_write("sic.hdf5",path,"vwanmt",&
              vwanmt(1,1,1,itloc,ispn,n),(/lmmaxvr,nrmtmax,natmtot/))
            call hdf5_write("sic.hdf5",path,"vwanir",&
              vwanir(1,itloc,ispn,n),(/ngrtot/))
            call hdf5_write("sic.hdf5",path,"wanmt",&
              wanmt(1,1,1,itloc,ispn,n),(/lmmaxvr,nrmtmax,natmtot/))
            call hdf5_write("sic.hdf5",path,"wanir",&
              wanir(1,itloc,ispn,n),(/ngrtot/))
          enddo
        enddo
      enddo
    endif
    call mpi_grid_barrier(dims=(/dim_t/))
  enddo
endif
if (wproc) close(151)
deallocate(h0wan,vsic)
deallocate(wanmt,wanir,vwanmt,vwanir)
return
end

