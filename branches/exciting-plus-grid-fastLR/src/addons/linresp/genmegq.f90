#ifdef _HDF5_
subroutine genmegq(ivq0m,wfsvmtloc,wfsvitloc,ngknr,igkignr,pmat)
use modmain
implicit none
! arguments
! q-vector in k-mesh coordinates
integer, intent(in) :: ivq0m(3)
complex(8), intent(in) :: wfsvmtloc(lmmaxvr,nrfmax,natmtot,nspinor,nstsv,nkptnrloc)
complex(8), intent(in) :: wfsvitloc(ngkmax,nspinor,nstsv,nkptnrloc)
integer, intent(in) :: ngknr(nkptnrloc)
integer, intent(in) :: igkignr(ngkmax,nkptnrloc)
complex(8), intent(in) :: pmat(3,nstsv,nstsv,nkptnrloc)

! allocatable arrays
integer, allocatable :: igkignr2(:)
complex(8), allocatable :: wfsvmt2(:,:,:,:,:)
complex(8), allocatable :: wfsvit2(:,:,:)

integer i,ikstep,sz,complete
integer ngknr2

integer nkstep
real(8) t1,t2,t3,t4,t5,dn1

integer lmaxexp,lmmaxexp

character*100 :: qnm,fout,fme,fu

logical exist


! comment:
! the subroutine computes <psi_{n,k}|e^{-i(G+q)x}|psi_{n',k+q}> 
! 
! switch write_megq_file controls the reading and writing of ME file
! when we write ME we have two choices: write to single file or write
!  to multiple files

! maximum l for exponent expansion
lmaxexp=lmaxvr+2
lmmaxexp=(lmaxexp+1)**2

call qname(ivq0m,qnm)
qnm="./"//trim(qnm)//"/"//trim(qnm)
wproc=.false.
if (mpi_grid_root((/dim_k,dim_b/))) then
  wproc=.true.
  fout=trim(qnm)//"_ME.OUT"
  open(150,file=trim(fout),form='formatted',status='replace')
endif

complete=0
fme=trim(qnm)//"_me.hdf5"
if (mpi_grid_root((/dim_k,dim_b/))) then
  inquire(file=trim(fme),exist=exist)
  if (exist) then
    call read_integer(complete,1,trim(fme),'/parameters','complete')
  endif
endif
call mpi_grid_bcast(complete,dims=(/dim_k,dim_b/))
if (complete.eq.1) goto 30

if (crpa) then
  if (mpi_grid_root((/dim_k,dim2/))) then
    fu=trim(qnm)//"_U"
    inquire(file=trim(fu),exist=exist)
  endif
  call mpi_grid_bcast(exist,dims=(/dim_k,dim2/))
  if (exist) goto 30
endif

if (wproc) then
  write(150,*)
  write(150,'("Calculation of matrix elements:")')
  write(150,'("  <n,k|e^{-i(G+q)x}|n'',k+q>")')
endif

call timer_start(1,reset=.true.)
! initialize G, q and G+q vectors
call init_g_q_gq(ivq0m,lmaxexp,lmmaxexp)
! initialize k+q array
call init_kq
! initialize interband transitions
call init_band_trans
! initialize Gaunt-like coefficients 
call init_gntuju(lmaxexp)
call timer_stop(1)

if (wproc) then
  write(150,*)
  write(150,'("G-shell limits      : ",2I4)')gshme1,gshme2
  write(150,'("G-vector limits     : ",2I4)')gvecme1,gvecme2
  write(150,'("number of G-vectors : ",I4)')ngvecme   
  write(150,*)
  write(150,'("q-vector (lat.coord.)                        : ",&
    & 3G18.10)')vq0l
  write(150,'("q-vector (Cart.coord.) [a.u.]                : ",&
    & 3G18.10)')vq0c
  write(150,'("q-vector length [a.u.]                       : ",&
    & G18.10)')sqrt(vq0c(1)**2+vq0c(2)**2+vq0c(3)**2)
  write(150,'("q-vector length [1/A]                        : ",&
    & G18.10)')sqrt(vq0c(1)**2+vq0c(2)**2+vq0c(3)**2)/au2ang
  write(150,'("G-vector to reduce q to first BZ (lat.coord.): ",&
    & 3I4)')ivg(:,lr_igq0)
  write(150,'("index of G-vector                            : ",&
    & I4)')lr_igq0
  write(150,'("reduced q-vector (lat.coord.)                : ",&
    & 3G18.10)')vq0rl
  write(150,'("reduced q-vector (Cart.coord.) [a.u.]        : ",&
    & 3G18.10)')vq0rc
  write(150,*)
  write(150,'("Bloch functions band interval (N1,N2 or E1,E2) : ",2F8.3)')&
    lr_e1,lr_e2
  if (wannier_megq) then
    write(150,'("Wannier functions band interval (N1,N2 or E1,E2) : ",2F8.3)')&
      lr_e1_wan,lr_e2_wan
  endif
  write(150,*)
  write(150,'("Minimal energy transition (eV) : ",F12.6)')lr_min_e12*ha2ev    
  write(150,*)
  write(150,'("Maximum number of interband transitions: ",I5)')nmegqblhmax
  sz=int(16.d0*ngvecme*nmegqblhlocmax*nkptnrloc/1048576.d0)
  write(150,*)
  write(150,'("Array size of matrix elements in Bloch basis (MB) : ",I6)')sz
  if (wannier_megq) then
    sz=int(16.d0*nmegqwan*ntrmegqwan*ngvecme/1048576.d0)
    write(150,*)
    write(150,'("Number of WF transitions : ",I4)')nmegqwan
    write(150,'("Number of WF translations : ",I4)')ntrmegqwan
    write(150,'("Array size of matrix elements in Wannier basis (MB) : ",I6)')sz
  endif   
  sz=int(24.d0*ngntujumax*natmcls*ngvecme/1048576.d0)
  write(150,*)
  write(150,'("Maximum number of Gaunt-like coefficients : ",I8)')ngntujumax
  write(150,'("Array size of Gaunt-like coefficients (MB) : ",I6)')sz
  write(150,*)
  write(150,'("Init done in ",F8.2," seconds")')timer_get_value(1)
  call flushifc(150)
endif

if (allocated(megqblh)) deallocate(megqblh)
allocate(megqblh(nmegqblhlocmax,ngvecme,nkptnrloc))
megqblh(:,:,:)=zzero
if (wannier_megq) then
  if (allocated(megqwan)) deallocate(megqwan)
  allocate(megqwan(nmegqwan,ntrmegqwan,ngvecme))
  megqwan(:,:,:)=zzero
endif

if (write_megq_file) call write_me_header(qnm)


allocate(wfsvmt2(lmmaxvr,nrfmax,natmtot,nspinor,nstsv))
allocate(wfsvit2(ngkmax,nspinor,nstsv))
allocate(igkignr2(ngkmax))

i=0
nkstep=mpi_grid_map(nkptnr,dim_k,x=i)
call timer_reset(1)
call timer_reset(2)
call timer_reset(3)
call timer_reset(4)
call timer_reset(5)
do ikstep=1,nkstep
! transmit wave-functions
  call timer_start(1)
  call getwfkq(ikstep,wfsvmtloc,wfsvitloc,ngknr,igkignr,wfsvmt2, &
    wfsvit2,ngknr2,igkignr2)
  call timer_stop(1)
! compute matrix elements  
  call timer_start(2)
  if (ikstep.le.nkptnrloc) then
    call genmegqblh(ikstep,ngknr(ikstep),ngknr2,igkignr(1,ikstep),igkignr2, &
      wfsvmtloc(1,1,1,1,1,ikstep),wfsvmt2,wfsvitloc(1,1,1,ikstep),wfsvit2)
! add contribution from k-point to the matrix elements of e^{-i(G+q)x} in 
!  the basis of Wannier functions
    if (wannier_megq) then
      call genmegqwan(ikstep)
    endif !wannier
  endif !ikstep.le.nkptnrloc
  call timer_stop(2)
enddo !ikstep
! time for wave-functions send/recieve
t1=timer_get_value(1)
! total time for matrix elements calculation
t2=timer_get_value(2)
call mpi_grid_reduce(t2,dims=(/dim_k,dim_b/),side=.true.)
! time to precompute MT
t3=timer_get_value(3)
call mpi_grid_reduce(t3,dims=(/dim_k,dim_b/),side=.true.)
! time to precompute IT
t4=timer_get_value(4)
call mpi_grid_reduce(t4,dims=(/dim_k,dim_b/),side=.true.)
! time to compute ME
t5=timer_get_value(5)
call mpi_grid_reduce(t5,dims=(/dim_k,dim_b/),side=.true.)
! approximate number of matrix elements
dn1=1.d0*nmegqblhmax*ngvecme*nkptnr
if (wannier_megq) dn1=dn1+1.d0*nmegqwan*ntrmegqwan*ngvecme
if (wproc) then
  write(150,*)
  write(150,'("Average time (seconds)")')
  write(150,'("  send and receive wave-functions  : ",F8.2)')t1
  write(150,'("  compute matrix elements          : ",F8.2)')t2/mpi_grid_nproc
  write(150,'("    precompute muffin-tin part     : ",F8.2)')t3/mpi_grid_nproc
  write(150,'("    precompute interstitial part   : ",F8.2)')t4/mpi_grid_nproc
  write(150,'("    multiply wave-functions        : ",F8.2)')t5/mpi_grid_nproc
  write(150,'("Speed (me/sec)                     : ",F10.2)')mpi_grid_nproc*dn1/t2
  call flushifc(150)
endif

if (wannier_megq) then
! sum over all k-points and interband transitions to get <n,T=0|e^{-i(G+q)x|n',T'>
  call mpi_grid_reduce(megqwan(1,1,1),nmegqwan*ntrmegqwan*ngvecme,&
    dims=(/dim_k,dim_b/))
  megqwan=megqwan/nkptnr
endif

if (write_megq_file) then
  if (wproc) then
    write(150,*)
    write(150,'("Writing matrix elements")')
  endif
  call timer_start(3,reset=.true.)
  call write_me(qnm,pmat)
  call timer_stop(3)
  if (wproc) write(150,'(" Done in : ",F8.2)')timer_get_value(3)
endif  

! deallocate arrays if we saved the ME file
if (write_megq_file) then
  deallocate(megqblh)
  deallocate(nmegqblh)
  deallocate(bmegqblh)
  deallocate(idxkq)
  if (wannier_megq) then
    deallocate(bmegqwan)
    deallocate(itrmegqwan)
    deallocate(megqwan)
  endif
endif

deallocate(wfsvmt2)
deallocate(wfsvit2)
deallocate(igkignr2)
!deallocate(ngntuju)
!deallocate(gntuju)
!deallocate(igntuju)
!if (spinpol) then
!  deallocate(spinor_ud)
!endif

!if (wannier_megq) then
!  deallocate(nmegqblhwan)
!  deallocate(imegqblhwan)
!endif

if (mpi_grid_root((/dim_k,dim_b/)).and.write_megq_file) then
  complete=1
  call rewrite_integer(complete,1,trim(fme),'/parameters','complete')
endif

call mpi_grid_barrier((/dim_k,dim_b/))

30 continue
if (wproc) then
  write(150,*)
  write(150,'("Done.")')
  call flushifc(150)
endif

return
end
#endif
