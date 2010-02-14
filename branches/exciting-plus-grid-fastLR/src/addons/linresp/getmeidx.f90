subroutine getmeidx(req)
use modmain
implicit none
! arguments
logical, intent(in) :: req

integer i,ik,jk,ist1,ist2,ikloc,n
logical laddme,ldocc
real(8) d1
logical l11,l12,l21,l22,le1,le2,lwann,le1w,le2w
integer, allocatable :: wann_bnd(:)
logical, external :: bndint
logical, external :: wann_diel

if (wannier_megq) then
  allocate(wann_bnd(nstsv))
  wann_bnd=0
! mark all bands that contribute to WF expansion
  do ikloc=1,nkptnrloc
    ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
    do i=1,nstsv
      do n=1,nwann
        if (abs(wann_c(n,i,ikloc)).gt.1d-10) wann_bnd(i)=1
      enddo
    enddo
  enddo
  call mpi_grid_reduce(wann_bnd(1),nstsv,dims=(/dim_k/),all=.true.,op=op_max)
! find lowest band
  do i=1,nstsv
    if (wann_bnd(i).ne.0) then
      lr_e1_wan=i 
      exit
    endif
  enddo
! find highest band
  do i=nstsv,1,-1
    if (wann_bnd(i).ne.0) then
      lr_e2_wan=i 
      exit
    endif
  enddo
endif !wannier
if (req) then
  nmegqblhmax=0
  lr_min_e12=100.d0
endif
do ikloc=1,nkptnrloc
  ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
  jk=idxkq(1,ik)
  i=0
  do ist1=1,nstsv
    do ist2=1,nstsv
      le1=bndint(ist1,lr_evalsvnr(ist1,ik),lr_e1,lr_e2)
      le2=bndint(ist2,lr_evalsvnr(ist2,jk),lr_e1,lr_e2)
      d1=lr_occsvnr(ist1,ik)-lr_occsvnr(ist2,jk)
      ldocc=abs(d1).gt.1d-5
      laddme=.false.
! comment:
!   include transition between bands ist1 and ist2 when:
!     1a. we are doing response in Bloch basis and difference of band 
!         occupation numbers in not zero     OR
!     1b. we are doing response in Wannier basis or constrained RPA
!     2.  both bands ist1 and ist2 fall into energy interval
      lwann=.false.
      if (wannier_megq) then
        le1w=bndint(ist1,lr_evalsvnr(ist1,ik),lr_e1_wan,lr_e2_wan)
        le2w=bndint(ist2,lr_evalsvnr(ist2,jk),lr_e1_wan,lr_e2_wan)
        if ((wannier_chi0_chi.and..not.wann_diel()).and.(le1w.and.le2w)) lwann=.true.
        if (crpa.and.(le1w.and.le2w)) lwann=.true.
      endif
      if ((ldocc.or.lwann).and.(le1.and.le2)) then
        if (.not.spinpol) then
          laddme=.true.
        else
          l11=spinor_ud(1,ist1,ik).eq.1.and.spinor_ud(1,ist2,jk).eq.1
          l12=spinor_ud(1,ist1,ik).eq.1.and.spinor_ud(2,ist2,jk).eq.1
          l21=spinor_ud(2,ist1,ik).eq.1.and.spinor_ud(1,ist2,jk).eq.1
          l22=spinor_ud(2,ist1,ik).eq.1.and.spinor_ud(2,ist2,jk).eq.1
          if (lrtype.eq.0.and.(l11.or.l22)) laddme=.true.
          if (lrtype.eq.1.and.(l12.or.l21)) laddme=.true.
        endif
      endif
      if (laddme) then
        i=i+1
        if (.not.req) then
          bmegqblh(1,i,ikloc)=ist1
          bmegqblh(2,i,ikloc)=ist2
          if (wannier_megq) then
            if (wann_bnd(ist1).ne.0.and.wann_bnd(ist2).ne.0) then
              nmegqblhwan(ikloc)=nmegqblhwan(ikloc)+1
              imegqblhwan(nmegqblhwan(ikloc),ikloc)=i
            endif
          endif
        endif
        if (req) then
          lr_min_e12=min(lr_min_e12,abs(lr_evalsvnr(ist1,ik)-lr_evalsvnr(ist2,jk)))
        endif
      endif
    enddo
  enddo
  if (.not.req) nmegqblh(ikloc)=i
  if (req) nmegqblhmax=max(nmegqblhmax,i)
enddo !ikloc

if (req) then
  call mpi_grid_reduce(lr_min_e12,dims=(/dim_k/),op=op_min)
endif

if (wannier_megq) then
  deallocate(wann_bnd)
endif

return
end

