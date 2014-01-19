MODULE localpot2_module

  use rgrid_module
  use localpot2_variables
  use watch_module

  implicit none

  PRIVATE
  PUBLIC :: test_localpot2, test2_localpot2, Lpot, vloc_nl, MLpot &
           ,read_localpot2, flag_localpot2, fecut_loc

  logical :: flag_localpot2 = .false.

  integer :: Nintp_loc
  real(8) :: fecut_loc

  integer :: MLpot
  integer,allocatable :: Lpot(:,:)
  real(8),allocatable :: vloc_nl(:,:)

CONTAINS


  SUBROUTINE read_localpot2(unit,rank)
    implicit none
    integer,intent(IN) :: unit,rank
    integer :: i
    character(5) :: cbuf,ckey
    flag_localpot2=.false.
    Ndens_loc=1
    Nintp_loc=1
    fecut_loc=1.0d0
    if ( rank == 0 ) then
       rewind unit
       do i=1,10000
          read(unit,*,END=999) cbuf
          call convert_capital(cbuf,ckey)
          if ( ckey == "NDLOC" ) then
             backspace(unit)
             read(unit,*) cbuf,Ndens_loc,Nintp_loc,fecut_loc
             exit
          end if
       end do
999    continue
       if ( Ndens_loc > 1 ) flag_localpot2=.true. 
       write(*,*) "Ndens_loc=",Ndens_loc
       write(*,*) "Nintp_loc=",Nintp_loc
       write(*,*) "fecut_loc=",fecut_loc
       write(*,*) "flag_localpot2=",flag_localpot2
    end if
    call send_localpot2
  END SUBROUTINE read_localpot2


  SUBROUTINE send_localpot2
    implicit none
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(Ndens_loc,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(Nintp_loc,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(fecut_loc,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(flag_localpot2,1,MPI_LOGICAL,0,MPI_COMM_WORLD,ierr)
  END SUBROUTINE send_localpot2


  SUBROUTINE test_localpot2
    implicit none
    integer :: ll_0,ll_1,i1,i2,j1
    real(8) :: x,y

    nitp_0 = min( 0, -Nintp_loc+1 )
    nitp_1 = Nintp_loc

    allocate( Clag1(nitp_0:nitp_1,0:Ndens_loc-1) ) ; Clag1=0.0d0
    allocate( Clag2(nitp_0:nitp_1,0:Ndens_loc-1) ) ; Clag2=0.0d0
    allocate( Clag3(nitp_0:nitp_1,0:Ndens_loc-1) ) ; Clag3=0.0d0

    do j1=0,Ndens_loc-1

       do i1=nitp_0,nitp_1

          Clag1(i1,j1)=1.d0

          do i2=nitp_0,nitp_1

             if ( i2 == i1 ) cycle

             x=dble(j1-i2*Ndens_loc)
             y=dble(i1-i2)*Ndens_loc

             Clag1(i1,j1)=Clag1(i1,j1)*(x/y)

          end do ! i2

       end do ! i1

    end do ! j1

    Clag2(:,:) = Clag1(:,:)
    Clag3(:,:) = Clag1(:,:)

  END SUBROUTINE test_localpot2


  SUBROUTINE test2_localpot2(ML1d,ML2d,ML3d,vpot)

    implicit none

    integer,intent(IN) :: ML1d,ML2d,ML3d
    real(8),intent(IN) :: vpot(0:ML1d-1,0:ML2d-1,0:ML3d-1)

    integer :: ic1,ic2,ic3,jd1,jd2,jd3,id1,id2,id3,ML,MK,i,ic,it,jt
    integer :: ML1,ML2,ML3,itp1,itp2,itp3,jtp1,jtp2,jtp3,i1,i2,i3
    integer :: iic1,iic2,iic3,j,jc1,jc2,jc3,k
    real(8) :: const,ct0,ct1,et0,et1
    real(8),allocatable :: w(:,:,:)
    integer,allocatable :: LLL(:,:,:),KKK(:,:,:),ichk(:)

    ML1 = Ngrid(1)
    ML2 = Ngrid(2)
    ML3 = Ngrid(3)

    call watch(ct0,et0)

    allocate( LLL(0:ML1-1,0:ML2-1,0:ML3-1) ) ; LLL=0
    i=0
    do ic3=0,ML3-1
    do ic2=0,ML2-1
    do ic1=0,ML1-1
       i=i+1
       LLL(ic1,ic2,ic3)=i
    end do
    end do
    end do
    ML=i
    allocate( KKK(nitp_0:nitp_1,nitp_0:nitp_1,nitp_0:nitp_1) ) ; KKK=0
    i=0
    do itp3=nitp_0,nitp_1
    do itp2=nitp_0,nitp_1
    do itp1=nitp_0,nitp_1
       i=i+1
       KKK(itp1,itp2,itp3)=i
    end do
    end do
    end do
    MK=i

    write(*,*) "ML,MK",ML,MK

    call watch(ct1,et1) ; write(*,*) "(1)",ct1-ct0,et1-et0

    allocate( w(ML,MK,MK) ) ; w=0.0d0

    do ic3=0,ML3-1
    do jd3=0,Ndens_loc-1
       id3=ic3*Ndens_loc+jd3

       do ic2=0,ML2-1
       do jd2=0,Ndens_loc-1
          id2=ic2*Ndens_loc+jd2

          do ic1=0,ML1-1
          do jd1=0,Ndens_loc-1
             id1=ic1*Ndens_loc+jd1

             do jtp3=nitp_0,nitp_1
             do itp3=nitp_0,nitp_1

                do jtp2=nitp_0,nitp_1
                do itp2=nitp_0,nitp_1

                   do jtp1=nitp_0,nitp_1
                   do itp1=nitp_0,nitp_1

                      ic = LLL(ic1,ic2,ic3)
                      it = KKK(itp1,itp2,itp3)
                      jt = KKK(jtp1,jtp2,jtp3)

                      w(ic,it,jt) = w(ic,it,jt) &
                    + Clag1(itp1,jd1)*Clag2(itp2,jd2)*Clag3(itp3,jd3) &
                    * vpot(id1,id2,id3) &
                    * Clag1(jtp1,jd1)*Clag2(jtp2,jd2)*Clag3(jtp3,jd3)

                   end do
                   end do

                end do
                end do

             end do
             end do

          end do
          end do

       end do
       end do

    end do
    end do

    call watch(ct0,et0) ; write(*,*) "(2)",ct0-ct1,et0-et1

!
! ---
!

    allocate( ichk(ML) ) ; ichk=0

    do ic3=0,ML3-1
    do ic2=0,ML2-1
    do ic1=0,ML1-1

       ic = LLL(ic1,ic2,ic3)

       do itp3=nitp_0,nitp_1
       do itp2=nitp_0,nitp_1
       do itp1=nitp_0,nitp_1

          it = KKK(itp1,itp2,itp3)

          iic1 = mod(ic1+itp1+ML1,ML1)
          iic2 = mod(ic2+itp2+ML2,ML2)
          iic3 = mod(ic3+itp3+ML3,ML3)

          i = LLL(iic1,iic2,iic3)

          do jtp3=nitp_0,nitp_1
          do jtp2=nitp_0,nitp_1
          do jtp1=nitp_0,nitp_1

             jt = KKK(jtp1,jtp2,jtp3)

             jc1 = mod(ic1+jtp1+ML1,ML1)
             jc2 = mod(ic2+jtp2+ML2,ML2)
             jc3 = mod(ic3+jtp3+ML3,ML3)

             j = LLL(jc1,jc2,jc3)

             if ( i == 1 ) then
                ichk(j) = ichk(j) + 1
             end if

          end do
          end do
          end do

       end do
       end do
       end do

    end do
    end do
    end do

    MLpot = count( ichk /= 0 )

    write(*,*) "MLpot=",MLpot
!    j=0
!    do i=1,ML
!       if ( ichk(i) /= 0 ) then
!          j=j+1
!          write(*,*) j,i,ichk(i)
!       end if
!    end do

    deallocate( ichk )

    call watch(ct1,et1) ; write(*,*) "(3)",ct1-ct0,et1-et0

!
! ---
!

    if ( allocated(Lpot) ) then
       Lpot=0
       vloc_nl=0.0d0
    else
       allocate( Lpot(MLpot,ML) ) ; Lpot=0
       allocate( vloc_nl(MLpot,ML) ) ; vloc_nl=0.0d0
    end if

    const=dble(ML)/dble(ML1d*ML2d*ML3d)

    allocate( ichk(ML) ) ; ichk=0

    do ic3=0,ML3-1
    do ic2=0,ML2-1
    do ic1=0,ML1-1

       ic = LLL(ic1,ic2,ic3)

       do itp3=nitp_0,nitp_1
       do itp2=nitp_0,nitp_1
       do itp1=nitp_0,nitp_1

          it = KKK(itp1,itp2,itp3)

          iic1 = mod(ic1+itp1+ML1,ML1)
          iic2 = mod(ic2+itp2+ML2,ML2)
          iic3 = mod(ic3+itp3+ML3,ML3)

          i = LLL(iic1,iic2,iic3)

          do jtp3=nitp_0,nitp_1
          do jtp2=nitp_0,nitp_1
          do jtp1=nitp_0,nitp_1

             jt = KKK(jtp1,jtp2,jtp3)

             jc1 = mod(ic1+jtp1+ML1,ML1)
             jc2 = mod(ic2+jtp2+ML2,ML2)
             jc3 = mod(ic3+jtp3+ML3,ML3)

             j = LLL(jc1,jc2,jc3)

             do k=1,ichk(i)
                if ( Lpot(k,i) == j ) then
                   vloc_nl(k,i) = vloc_nl(k,i) + w(ic,it,jt)
                   exit
                end if
             end do
             if ( k > ichk(i) ) then
                ichk(i)=ichk(i)+1
                Lpot(ichk(i),i) = j
                vloc_nl(ichk(i),i) = vloc_nl(ichk(i),i) + w(ic,it,jt)
             end if

          end do
          end do
          end do

       end do
       end do
       end do

    end do
    end do
    end do

    vloc_nl(:,:)=vloc_nl(:,:)*const

    deallocate( ichk )

!    do i=1,ML
!       write(*,*) i,count(vloc_nl(:,i)/=0.0d0),sum(vloc_nl(:,i))
!    end do

    deallocate( w )
    deallocate( KKK )
    deallocate( LLL )

    call watch(ct0,et0) ; write(*,*) "(4)",ct0-ct1,et0-et1

  END SUBROUTINE test2_localpot2

END MODULE localpot2_module
