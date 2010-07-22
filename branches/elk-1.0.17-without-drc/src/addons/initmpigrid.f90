subroutine initmpigrid
use modmain
implicit none
integer, allocatable :: d(:)
integer i1,i2,nd
!------------------------!
!     parallel grid      !
!------------------------!
if (task.eq.0.or.task.eq.1.or.task.eq.22.or.task.eq.20.or.task.eq.822.or.task.eq.805) then
  nd=2
  allocate(d(nd))
  d=1
  if (nproc.le.nkpt) then
    d(dim_k)=nproc
  else
    d(dim_k)=nkpt
    d(dim2)=nproc/nkpt
  endif    
else
  nd=1
  allocate(d(nd))
  d=nproc
endif  
! overwrite default grid layout
if (lmpigrid) then
  d(1:nd)=mpigrid(1:nd) 
endif
call mpi_grid_initialize(d)
deallocate(d)
return
end