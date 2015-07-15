MODULE kinetic_module

  use rgrid_module, only: Hgrid,Igrid
  use kinetic_variables
  use kinetic_sol_0_module
  use kinetic_sol_1_module
  use kinetic_sol_simple_module
  use kinetic_mol_module
  use esm_kinetic_module
  use kinetic_fft_module
  use fd_module

  implicit none

  PRIVATE
  PUBLIC :: init_kinetic, op_kinetic &
           ,read_kinetic, read_oldformat_kinetic &
           ,SYStype

  integer :: SYStype=0

CONTAINS


  SUBROUTINE init_kinetic( aa, bb, MBZ, kbb, disp_switch )
    implicit none
    real(8),intent(IN) :: aa(3,3),bb(3,3)
    integer,intent(IN) :: MBZ
    real(8),intent(IN) :: kbb(3,MBZ)
    logical,intent(IN) :: disp_switch
    integer :: m,n,k,is,i
    real(8) :: c1,c2,c3,kx,ky,kz,pi2
    real(8) :: a1,a2,a3,H1,H2,H3
    complex(8),parameter :: zi=(0.d0,1.d0)
    real(8),allocatable :: nab(:),lap(:)
    logical :: first_time = .true.

    pi2 = 2.d0*acos(-1.d0)
    a1  = sqrt(sum(aa(1:3,1)**2))/pi2
    a2  = sqrt(sum(aa(1:3,2)**2))/pi2
    a3  = sqrt(sum(aa(1:3,3)**2))/pi2

    if ( first_time ) then

       first_time = .false.

       allocate( coef_lap(3,Md) ) ; coef_lap=0.0d0
       allocate( coef_nab(3,Md) ) ; coef_nab=0.0d0

       allocate( lap(-Md:Md) ) ; lap=0.d0
       allocate( nab(-Md:Md) ) ; nab=0.d0

       call get_coef_lapla_fd(Md,lap)
       call get_coef_nabla_fd(Md,nab)

       if ( disp_switch ) then
          do i=0,Md
             write(*,'(1x,2f12.8,2x,2f12.8)') lap(i),lap(-i),nab(i),nab(-i)
          end do
       end if

       call get_ggg_kinetic(aa,bb,ggg)

       if ( disp_switch ) write(*,'(1x,"ggg=",6f10.5)') ggg

       flag_n12 = .false.
       flag_n23 = .false.
       flag_n31 = .false.
       if ( ggg(4) /= 0.d0 ) flag_n12 = .true.
       if ( ggg(5) /= 0.d0 ) flag_n23 = .true.
       if ( ggg(6) /= 0.d0 ) flag_n31 = .true.

       H1 = Hgrid(1)
       H2 = Hgrid(2)
       H3 = Hgrid(3)

       c1 = -0.5d0*ggg(1)/H1**2
       c2 = -0.5d0*ggg(2)/H2**2
       c3 = -0.5d0*ggg(3)/H3**2

       coef_lap0 = lap(0)*(c1+c2+c3)
       do n=1,Md
          coef_lap(1,n)=lap(n)*c1
          coef_lap(2,n)=lap(n)*c2
          coef_lap(3,n)=lap(n)*c3
       end do

       do n=1,Md
          coef_nab(1,n)=nab(n)/H1
          coef_nab(2,n)=nab(n)/H2
          coef_nab(3,n)=nab(n)/H3
       end do

       if ( disp_switch ) then
          write(*,'(1x,3x,3x,a20,3x,a20)') "lap","coef_lap"
          write(*,'(1x,i3,3x,f20.15,3x,f20.15)') 0,lap(0),coef_lap0
          do n=1,Md
             write(*,'(1x,i3,3x,f20.15,3x,3f20.15)') n,lap(n),coef_lap(1:3,n)
          end do
          write(*,'(1x,3x,3x,a20,3x,a20)') "nab","coef_nab"
          do n=1,Md
             write(*,'(1x,i3,3x,f20.15,3x,3f20.15)') n,nab(n),coef_nab(1:3,n)
          end do
       end if

       deallocate( nab,lap )

!       call init_kinetic_sol_1( disp_switch )

    end if ! first_time

! -- k-dependent coefficient --

    if ( allocated(const_k2)  ) deallocate( const_k2  )
    if ( allocated(zcoef_kin) ) deallocate( zcoef_kin )
    if ( allocated(coef_nabk) ) deallocate( coef_nabk )
    allocate( coef_nabk(3,Md,MBZ)     ) ; coef_nabk=0.0d0
    allocate( zcoef_kin(3,-Md:Md,MBZ) ) ; zcoef_kin=(0.0d0,0.0d0)
    allocate( const_k2(0:MBZ)         ) ; const_k2=0.d0

    flag_nab = .false.
    do k=1,MBZ
       kx=bb(1,1)*kbb(1,k)+bb(1,2)*kbb(2,k)+bb(1,3)*kbb(3,k)
       ky=bb(2,1)*kbb(1,k)+bb(2,2)*kbb(2,k)+bb(2,3)*kbb(3,k)
       kz=bb(3,1)*kbb(1,k)+bb(3,2)*kbb(2,k)+bb(3,3)*kbb(3,k)
       c1=a1*( bb(1,1)*kx+bb(2,1)*ky+bb(3,1)*kz )
       c2=a2*( bb(1,2)*kx+bb(2,2)*ky+bb(3,2)*kz )
       c3=a3*( bb(1,3)*kx+bb(2,3)*ky+bb(3,3)*kz )
       if ( c1/=0.d0 .or. c2/=0.d0 .or. c3/=0.d0 ) flag_nab=.true.
       do n=1,Md
          coef_nabk(1,n,k)=coef_nab(1,n)*c1
          coef_nabk(2,n,k)=coef_nab(2,n)*c2
          coef_nabk(3,n,k)=coef_nab(3,n)*c3
       end do
       const_k2(k) = 0.5d0*( kx*kx + ky*ky + kz*kz )
    end do

    do k=1,MBZ
       do n=1,Md
          zcoef_kin(1:3,-n,k)=coef_lap(1:3,n)+zi*coef_nabk(1:3,n,k)
          zcoef_kin(1:3, n,k)=coef_lap(1:3,n)-zi*coef_nabk(1:3,n,k)
       end do
    end do

  END SUBROUTINE init_kinetic


  SUBROUTINE get_ggg_kinetic(aa,bb,ggg)
    implicit none
    real(8),intent(IN)  :: aa(3,3),bb(3,3)
    real(8),intent(OUT) :: ggg(6)
    real(8) :: const,a1,a2,a3
    const=1.d0/(4.d0*acos(-1.d0)**2)
    a1 = sqrt( sum( aa(:,1)**2 ) )
    a2 = sqrt( sum( aa(:,2)**2 ) )
    a3 = sqrt( sum( aa(:,3)**2 ) )
    ggg(1) = a1*a1*sum(bb(:,1)*bb(:,1))*const
    ggg(2) = a2*a2*sum(bb(:,2)*bb(:,2))*const
    ggg(3) = a3*a3*sum(bb(:,3)*bb(:,3))*const
    ggg(4) = a1*a2*sum(bb(:,1)*bb(:,2))*const
    ggg(5) = a2*a3*sum(bb(:,2)*bb(:,3))*const
    ggg(6) = a3*a1*sum(bb(:,3)*bb(:,1))*const
  END SUBROUTINE get_ggg_kinetic


  SUBROUTINE op_kinetic(k,tpsi,htpsi,n1,n2,ib1,ib2)
    implicit none
    integer,intent(IN) :: k,n1,n2,ib1,ib2
#ifdef _DRSDFT_
    real(8),intent(IN)  :: tpsi(n1:n2,ib1:ib2)
    real(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#else
    complex(8),intent(IN)  :: tpsi(n1:n2,ib1:ib2)
    complex(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#endif
    select case(SYStype)
    case default
!       call op_kinetic_sol_0(k,tpsi,htpsi,n1,n2,ib1,ib2)
       call op_kinetic_sol_1(k,tpsi,htpsi,n1,n2,ib1,ib2)
!       call op_kinetic_sol_simple(k,tpsi,htpsi,n1,n2,ib1,ib2)
!       call op_kinetic_fft(k,tpsi,htpsi,n1,n2,ib1,ib2)
    case(1)
       call op_kinetic_mol(n1,n2,ib1,ib2,tpsi,htpsi)
    case(3)
       call op_esm_kinetic(k,n1,n2,ib1,ib2,tpsi,htpsi)
    end select
  END SUBROUTINE op_kinetic


  SUBROUTINE read_kinetic(rank,unit)
    implicit none
    integer,intent(IN) :: rank,unit
    integer :: i
    character(7) :: cbuf,ckey
    Md = 6
    SYStype = 0
    if ( rank == 0 ) then
       rewind unit
       do i=1,10000
          read(unit,*,END=999) cbuf
          call convert_capital(cbuf,ckey)
          if ( ckey(1:2) == "MD" ) then
             backspace(unit)
             read(unit,*) cbuf,Md
          else if ( ckey(1:7) == "SYSTYPE" ) then
             backspace(unit)
             read(unit,*) cbuf,SYStype
          end if
       end do
999    continue
       write(*,*) "Md =",Md
       write(*,*) "SYStype =",SYStype
    end if
    call send_kinetic(0)
  END SUBROUTINE read_kinetic


  SUBROUTINE read_oldformat_kinetic(rank,unit)
    implicit none
    integer,intent(IN) :: rank,unit
    if ( rank == 0 ) then
       read(unit,*) Md, SYStype
       write(*,*) "Md =",Md
       write(*,*) "SYStype =",SYStype
    end if
    call send_kinetic(0)
  END SUBROUTINE read_oldformat_kinetic


  SUBROUTINE send_kinetic(rank)
    implicit none
    integer,intent(IN) :: rank
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(Md,1,MPI_INTEGER,rank,MPI_COMM_WORLD,ierr)
    call mpi_bcast(SYStype,1,MPI_INTEGER,rank,MPI_COMM_WORLD,ierr)
  END SUBROUTINE send_kinetic


END MODULE kinetic_module
