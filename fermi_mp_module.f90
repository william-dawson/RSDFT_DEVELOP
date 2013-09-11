MODULE fermi_module

  implicit none

  PRIVATE
  PUBLIC :: read_fermi,send_fermi,ekbt,calc_fermi &
           ,efermi, Eentropy

  real(8) :: ekbt, efermi, Eentropy
  integer :: mb1,mb2,kinteg

  logical :: first_time = .true.
  real(8),allocatable :: factor(:)

CONTAINS


  SUBROUTINE read_fermi(unit)
    implicit none
    integer,intent(IN) :: unit
    read(unit,*) ekbt,kinteg
    write(*,*) "ekbt=",ekbt
    write(*,*) "kinteg=",kinteg
  END SUBROUTINE read_fermi


  SUBROUTINE send_fermi(rank)
    implicit none
    integer,intent(IN) :: rank
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(ekbt,1,MPI_REAL8,rank,MPI_COMM_WORLD,ierr)
    call mpi_bcast(kinteg,1,MPI_INTEGER,rank,MPI_COMM_WORLD,ierr)
  END SUBROUTINE send_fermi


  SUBROUTINE calc_fermi(iter,nfixed,MB,MBZ,MSP,znel,dspn,esp,wbz,occ &
                       ,disp_switch)
    implicit none
    integer,intent(IN)  :: iter,nfixed,MB,MBZ,MSP
    logical,intent(IN)  :: disp_switch
    real(8),intent(IN)  :: esp(MB,MBZ,MSP),wbz(MBZ),znel,dspn
    real(8),intent(OUT) :: occ(MB,MBZ,MSP)
    real(8) :: ef1,ef2,ef,ef0
    integer :: ib,id,n,k,s,efconv
    real(8) :: zne,octmp,ff,xx
    real(8),parameter :: eps=0.d0
    integer,parameter :: mxcycl=1000

    if ( first_time ) then
       first_time = .false.
       if ( kinteg > 0 ) then
          allocate( factor(kinteg) )
          factor(1)=-1.d0/(4.d0*sqrt(acos(-1.d0)))
          do n=2,kinteg
             factor(n)=-factor(n-1)/(4.d0*n)
          end do
       end if
    end if

    mb1 = 1
    mb2 = MB

! Set upper & lower boundarires of Fermi energy

    ef1 = minval( esp(mb1:mb2,1:MBZ,1:MSP) )
    ef2 = maxval( esp(mb1:mb2,1:MBZ,1:MSP) )
    if ( ef1 == ef2 ) then
       ef1 = ef1 - 0.01d0
       ef2 = ef2 + 0.01d0
    end if

!C Safety margin for highly degenerate systems & artificial fault
!C
    ef2 = ef2 + min( ekbt*1.d2, 0.1d0 )

    if ( MSP == 1 .or. iter > Nfixed ) then

       zne = znel - 2.d0*(mb1-1)

       ef0 = 1.d10

       do id=1,mxcycl

          ef = 0.5d0*( ef1 + ef2 )
          if ( ef == ef0 ) goto 100
          octmp = 0.0d0

          do s=1,MSP
          do k=1,MBZ
          do n=mb1,mb2

             xx=(esp(n,k,s)-ef)/ekbt
             ff=ff0(kinteg,xx)

             octmp = octmp + ff*wbz(k)*2.d0/dble(MSP)
             occ(n,k,s)=ff

          end do
          end do
          end do

          if ( octmp-zne > eps ) then
             ef2=ef
          else if ( octmp-zne < -eps ) then
             ef1=ef
          else
             goto 100
          end if

          ef0 = ef

       end do ! id

    else

       efconv=0
       if ( DISP_SWITCH ) then
          write(*,*) "total spin density is fixed!!"
       end if

       do s=1,MSP

          ef1 = minval( esp(mb1:mb2,1:MBZ,s) )
          ef2 = maxval( esp(mb1:mb2,1:MBZ,s) )
          if ( ef1 == ef2 ) then
             ef1 = ef1 - 0.01d0
             ef2 = ef2 + 0.01d0
          end if
          ef2 = ef2 + min( ekbt*1.d2, 0.1d0 )

          zne = 0.5d0*znel + (3-2*s)*0.5d0*dspn

          do id=1,mxcycl

             ef = 0.5d0*(ef1+ef2)
             octmp = 0.0d0

             do n=mb1,mb2

                do k=1,MBZ

                   xx=(esp(n,k,s)-ef)/ekbt
                   ff=ff0(kinteg,xx)

                   octmp=octmp+ff*wbz(k)
                   occ(n,k,s)=ff

                end do

             end do

             if ( octmp-zne > eps ) then
                ef2=ef
             else if ( octmp-zne < -eps ) then
                ef1=ef
             else
                efconv=efconv+1
                exit
             end if

          end do ! id

       end do ! s

       if ( efconv == 2 ) goto 100

    end if

    if ( abs(octmp-zne) > 1.d-10 ) then
       if ( disp_switch ) then
          write(6,*)' EF IS NOT CONVERGED'
          write(6,*)' Check the # of electron, mb1, and mb2'
          write(6,*)' EF1 & EF2=',ef1,ef2
          write(6,*)' octmp,zne=',octmp,zne,octmp-zne
          do s=1,MSP
             do k=1,MBZ
                write(*,*) "s,k =",s,k
                do n=mb1,mb2
                   write(*,*) n,occ(n,k,s),esp(n,k,s)
                end do
             end do
          end do
       end if
       stop'FERMI'
    end if

100 continue

    efermi   = ef
    Eentropy = 0.d0

    do s=1,MSP
    do k=1,MBZ
       do n=1,mb1-1
          occ(n,k,s)=2.d0*wbz(k)/dble(MSP)
       end do
       do n=mb1,mb2
          occ(n,k,s)=2.d0*occ(n,k,s)*wbz(k)/dble(MSP)
       end do
       do n=mb2+1,MB
          occ(n,k,s)=0.d0
       end do
    end do
    end do

  END SUBROUTINE calc_fermi

  FUNCTION ff0(n,x)
    implicit none
    integer :: n,i
    real(8) :: x,ff,ff0,hp0,hp1,hp2,hp3
!    INTERFACE
!       FUNCTION bberf(x)
!         real(8) :: bberf,x
!       END FUNCTION bberf
!    END INTERFACE
!    ff0 = 0.5d0*(1.d0-bberf(x))
    ff0 = 0.5d0*(1.d0-erf(x))
    if ( n <= 0 ) return
    hp0 = 1.d0
    hp1 = 2.d0*x
    ff  = factor(1)*hp1
    do i=2,n
       hp2 = 2.d0*x*hp1 - 2.d0*(2*i-3)*hp0
       hp3 = 2.d0*x*hp2 - 2.d0*(2*i-2)*hp1
       ff  = ff + factor(i)*hp3
       hp0 = hp2
       hp1 = hp3
    end do
    ff0 = ff0 + ff*exp(-x*x)
    return
  END FUNCTION ff0

END MODULE fermi_module
