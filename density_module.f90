MODULE density_module

  use wf_module
  use parallel_module
  use symmetry_module, only: sym_rho

  implicit none

  PRIVATE
  PUBLIC :: rho,init_density,normalize_density,calc_density

  real(8),allocatable :: rho(:,:)

  integer :: ML_RHO, ML_0_RHO, ML_1_RHO
  integer :: MS_RHO, MS_0_RHO, MS_1_RHO

  real(8) :: Nelectron_RHO, dV_RHO

CONTAINS


  SUBROUTINE init_density(Nelectron,dV)
    implicit none
    real(8),intent(IN) :: Nelectron,dV

    Nelectron_RHO = Nelectron
    dV_RHO        = dV

    ML_RHO   = sum( ir_grid )
    ML_0_RHO = id_grid(myrank_g) + 1
    ML_1_RHO = id_grid(myrank_g) + ir_grid(myrank_g)

    MS_RHO   = sum( ir_spin )
    MS_0_RHO = id_spin(myrank_s) + 1
    MS_1_RHO = ir_spin(myrank_s) + id_spin(myrank_s)

    if ( .not. allocated(rho) ) then
       allocate( rho(ML_0_RHO:ML_1_RHO,MS_RHO) )
       rho=0.0d0
       call random_number(rho)
       call normalize_density
    end if
  END SUBROUTINE init_density


  SUBROUTINE normalize_density
    implicit none
    real(8) :: c,d
    integer :: ierr
    c=sum(rho)*dV_RHO
    call mpi_allreduce(c,d,1,MPI_REAL8,MPI_SUM,comm_grid,ierr)
    c=Nelectron_RHO/d
    rho=c*rho
  END SUBROUTINE normalize_density


  SUBROUTINE calc_density
    implicit none
    integer :: n,k,s
    rho(:,:)=0.0d0
    do s=MS_0_WF,MS_1_WF
    do k=MK_0_WF,MK_1_WF
    do n=MB_0_WF,MB_1_WF
       rho(:,s)=rho(:,s)+occ(n,k,s)*abs( unk(:,n,k,s) )**2
    end do
    end do
    end do
    call sym_rho( ML_0_RHO, ML_1_RHO, MS_RHO, MS_0_RHO, MS_1_RHO, rho )
    call reduce_and_gather
    call write_info_density
  END SUBROUTINE calc_density


  SUBROUTINE reduce_and_gather
    implicit none
    integer :: s,m,ierr
    m=ML_1_RHO-ML_0_RHO+1
    do s=MS_0_RHO,MS_1_RHO
       call mpi_allreduce(MPI_IN_PLACE,rho(ML_0_RHO,s) &
            ,m,mpi_real8,mpi_sum,comm_band,ierr)
       call mpi_allreduce(MPI_IN_PLACE,rho(ML_0_RHO,s) &
            ,m,mpi_real8,mpi_sum,comm_bzsm,ierr)
    end do
! The following assumes all 'MSP_1-MSP_0+1' are the same
    m=m*(MS_1_RHO-MS_0_RHO+1)
    call mpi_allgather(rho(ML_0_RHO,MS_0_RHO),m &
         ,mpi_real8,rho,m,mpi_real8,comm_spin,ierr)
  END SUBROUTINE reduce_and_gather


  SUBROUTINE write_info_density
    implicit none
    integer :: ierr
    real(8) :: QQQ_0(2),QQQ_1(2)
    if ( MS_RHO == 2 ) then
       QQQ_0(1)=sum(     rho(:,1)-rho(:,MS_RHO)  )
       QQQ_0(2)=sum( abs(rho(:,1)-rho(:,MS_RHO)) )
       call mpi_allreduce( QQQ_0,QQQ_1,2,mpi_real8,mpi_sum,comm_grid,ierr)
       if ( disp_switch_parallel ) then
          write(*,*) "QQQ1    = ",QQQ_1(1)*dV_RHO
          write(*,*) "QQQ2    = ",QQQ_1(2)*dV_RHO
       end if
    end if
  END SUBROUTINE write_info_density


END MODULE density_module
