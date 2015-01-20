MODULE fock_module

  use xc_hybrid_module, only: occ_hf, unk_hf, iflag_hybrid, alpha_hf &
                             ,FKMB_0,FKMB_1,FKBZ_0,FKBZ_1,FOCK_0,FOCK_1 &
                             ,occ_factor,gamma_hf
  use array_bound_module, only: ML_0,ML_1,MB,MB_0,MB_1,MBZ_0,MBZ_1,MSP_0,MSP_1
  use wf_module, only: unk, occ, hunk
  use fock_fft_module
  use fock_cg_module
  use parallel_module

  implicit none

  PRIVATE
  PUBLIC :: Fock, op_fock, UpdateWF_fock

#ifdef _DRSDFT_
  real(8),parameter :: zero = 0.0d0
  integer,parameter :: TYPE_MAIN = MPI_REAL8
#else
  complex(8),parameter :: zero = (0.0d0,0.0d0)
  integer,parameter :: TYPE_MAIN = MPI_COMPLEX16
#endif

  integer :: SYStype=0

CONTAINS


  SUBROUTINE Fock( n,k,s, n1,n2, psi, tpsi )
    implicit none
    integer,intent(IN) :: n,k,s,n1,n2
#ifdef _DRSDFT_
    real(8),intent(IN)  :: psi(n1:n2)
    real(8),intent(INOUT) :: tpsi(n1:n2)
    real(8),allocatable :: trho(:),tvht(:)
    integer,parameter :: TYPE_MAIN = MPI_REAL8
#else
    complex(8),intent(IN)  :: psi(n1:n2)
    complex(8),intent(INOUT) :: tpsi(n1:n2)
    complex(8),allocatable :: trho(:),tvht(:)
    integer,parameter :: TYPE_MAIN = MPI_COMPLEX16
#endif
    real(8) :: c
    integer :: ML0,m,q,i,t,ierr

    ML0 = n2 - n1 + 1

    allocate( trho(n1:n2) ) ; trho=zero
    allocate( tvht(n1:n2) ) ; tvht=zero

    if ( gamma_hf == 0 ) then

       do t=FOCK_0,FOCK_1

          if ( t == 1 ) then

             do q=FKBZ_0,FKBZ_1

                do m=FKMB_0,FKMB_1

                   if ( abs(occ_hf(m,q,s)) < 1.d-10 ) cycle

                   c = occ_factor*occ_hf(m,q,s)*alpha_hf

                   do i=n1,n2
#ifdef _DRSDFT_
                      trho(i) = unk_hf(i,m,q,s)*psi(i)
#else   
                      trho(i) = conjg(unk_hf(i,m,q,s))*psi(i)
#endif
                   end do ! i

                   call Fock_fft(n1,n2,k,q,trho,tvht,t)
!                   call Fock_fft_parallel(n1,n2,k,q,trho,tvht,t)

                   do i=n1,n2
                      tpsi(i)=tpsi(i)-c*tvht(i)*unk_hf(i,m,q,s)
                   end do

                end do ! m

             end do ! q

          else ! [ t /= 1 ]

             do q=FKBZ_0,FKBZ_1

                do m=FKMB_0,FKMB_1

                   if ( abs(occ_hf(m,q,s))<1.d-10 ) cycle

                   c = occ_factor*occ_hf(m,q,s)*alpha_hf

                   do i=n1,n2
                      trho(i)=unk_hf(i,m,q,s)*psi(i)
                   end do

                   call Fock_fft(n1,n2,k,q,trho,tvht,t)
!                   call Fock_fft_parallel(n1,n2,k,q,trho,tvht,t)

                   do i=n1,n2
#ifdef _DRSDFT_
                      tpsi(i)=tpsi(i)-c*tvht(i)*unk_hf(i,m,q,s)
#else
                      tpsi(i)=tpsi(i)-c*tvht(i)*conjg(unk_hf(i,m,q,s))
#endif
                   end do ! i

                end do ! m

             end do ! q

          end if ! [ t ]

       end do ! t

!       trho(:)=tpsi(:)
!       call mpi_allreduce(trho,tpsi,ML0,TYPE_MAIN,mpi_sum,comm_fkmb,ierr)
!       call mpi_allreduce(tpsi,trho,ML0,TYPE_MAIN,mpi_sum,comm_fkbz,ierr)
!       call mpi_allreduce(trho,tpsi,ML0,TYPE_MAIN,mpi_sum,comm_fock,ierr)

    else ! [ gamma_hf /= 0 ]

       q = k

       do m=FKMB_0,FKMB_1

          if ( abs(occ_hf(m,q,s)) < 1.d-10 ) cycle

          do i=n1,n2
#ifdef _DRSDFT_
             trho(i) = unk_hf(i,m,q,s)*psi(i)
#else   
             trho(i) = conjg(unk_hf(i,m,q,s))*psi(i)
#endif
          end do

          if ( SYStype == 1 ) then
             call Fock_cg( n1,n2,k,q,trho,tvht,1 )
          else
             call Fock_fft(n1,n2,k,q,trho,tvht,1)
!            call Fock_fft_parallel(n1,n2,k,q,trho,tvht,1)
          end if

          c = alpha_hf*(2.0d0*occ_factor)*occ_hf(m,q,s)

          do i=n1,n2
             tpsi(i)=tpsi(i)-c*tvht(i)*unk_hf(i,m,q,s)
          end do

       end do ! m

!       trho(:)=tpsi(:)
!       call mpi_allreduce(trho,tpsi,ML0,TYPE_MAIN,mpi_sum,comm_fkmb,ierr)

    end if ! [ gamma_hf ]

    deallocate( tvht ) 
    deallocate( trho )

    return

  END SUBROUTINE Fock


  SUBROUTINE op_fock(k,s,n1,n2,ib1,ib2,tpsi,htpsi)
    implicit none
    integer,intent(IN) :: k,s,n1,n2,ib1,ib2
#ifdef _DRSDFT_
    real(8),intent(IN) :: tpsi(n1:n2,ib1:ib2)
    real(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#else
    complex(8),intent(IN) :: tpsi(n1:n2,ib1:ib2)
    complex(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#endif
    integer :: ib,i

    if ( iflag_hybrid == 0 ) return

    if ( iflag_hybrid == 2 ) then

       do ib=ib1,ib2
          do i=n1,n2
             htpsi(i,ib)=htpsi(i,ib)+alpha_hf*hunk(i,ib,k,s)
          end do
       end do

    else if ( iflag_hybrid > 0 ) then

       do ib=ib1,ib2
          call Fock( ib, k, s, n1, n2, tpsi(n1,ib), htpsi(n1,ib) )
       end do

    end if

  END SUBROUTINE op_fock


  SUBROUTINE UpdateWF_fock( SYStype_in )
    implicit none
    integer,optional,intent(IN) :: SYStype_in
    integer :: s,k,n,m,ierr

    if ( present(SYStype_in) ) SYStype = SYStype_in

    if ( disp_switch_parallel ) write(*,*) "UpdateWF_fock"

    occ_hf(:,:,:)   = 0.0d0
    unk_hf(:,:,:,:) = zero

    do s=MSP_0,MSP_1
    do k=MBZ_0,MBZ_1
    do n=MB_0 ,MB_1

       if ( n < FKMB_0 .or. FKMB_1 < n .or. k < FKBZ_0 .or. FKBZ_1 < k ) cycle

       unk_hf(:,n,k,s) = unk(:,n,k,s)

       occ_hf(n,k,s) = occ(n,k,s)

    end do ! n
    end do ! k
    end do ! s

    m = size( unk_hf(:,:,FKBZ_0,MSP_0) )
    do s=MSP_0,MSP_1
    do k=MBZ_0,MBZ_1
       call MPI_ALLREDUCE( MPI_IN_PLACE, unk_hf(:,:,k,s), m, TYPE_MAIN &
            ,MPI_SUM, comm_band, ierr )
    end do ! k
    end do ! s
    m = size( unk_hf(:,:,:,MSP_0) )
    do s=MSP_0,MSP_1
       call MPI_ALLREDUCE( MPI_IN_PLACE, unk_hf(:,:,:,s), m, TYPE_MAIN &
            ,MPI_SUM, comm_bzsm, ierr )
    end do ! s

    m = size( occ_hf(:,FKBZ_0,MSP_0) )
    do s=MSP_0,MSP_1
    do k=MBZ_0,MBZ_1
       call MPI_ALLREDUCE( MPI_IN_PLACE, occ_hf(:,k,s), m, MPI_REAL8 &
            ,MPI_SUM, comm_band, ierr )
    end do ! k
    end do ! s
    m = size( occ_hf(:,:,MSP_0) )
    do s=MSP_0,MSP_1
       call MPI_ALLREDUCE( MPI_IN_PLACE, occ_hf(:,:,s), m, MPI_REAL8 &
            ,MPI_SUM, comm_bzsm, ierr )
    end do ! s

    hunk(:,:,:,:) = zero
    ct_fock_fft(:)=0.0d0
    et_fock_fft(:)=0.0d0

    do s=MSP_0,MSP_1
    do k=MBZ_0,MBZ_1
#ifdef _DRSDFT_
!       call Fock_2( k,s,ML_0,ML_1 )
       call Fock_4( k,s,ML_0,ML_1 )
#else
       do n=MB_0 ,MB_1
          call Fock( n,k,s, ML_0,ML_1, unk(ML_0,n,k,s), hunk(ML_0,n,k,s) )
       end do ! n
#endif
    end do ! k
    end do ! s

    if ( disp_switch_parallel ) then
       write(*,*) "time(fock_fft1)=",ct_fock_fft(1),et_fock_fft(1)
       write(*,*) "time(fock_fft2)=",ct_fock_fft(2),et_fock_fft(2)
       write(*,*) "time(fock_fft3)=",ct_fock_fft(3),et_fock_fft(3)
       write(*,*) "time(fock_fft4)=",ct_fock_fft(4),et_fock_fft(4)
       write(*,*) "time(fock_fft5)=",ct_fock_fft(5),et_fock_fft(5)
    end if

  END SUBROUTINE UpdateWF_fock


  SUBROUTINE Fock_2( k,s,n1,n2 )
    implicit none
    integer,intent(IN) :: k,s,n1,n2
#ifdef _DRSDFT_
    real(8),allocatable :: trho(:),tvht(:)
#else
    complex(8),allocatable :: trho(:),tvht(:)
#endif
    real(8) :: c
    integer :: m,n,i

    allocate( trho(n1:n2) ) ; trho=zero
    allocate( tvht(n1:n2) ) ; tvht=zero

! --- occupied oribitals

    do n=MB_0,MB_1

       if ( abs(occ(n,k,s)) < 1.d-10 ) cycle

       do m=MB_0,n

          if ( abs(occ(m,k,s)) < 1.d-10 ) cycle

          do i=n1,n2
#ifdef _DRSDFT_
             trho(i) = unk(i,m,k,s)*unk(i,n,k,s)
#else   
             trho(i) = conjg(unk(i,m,k,s))*unk(i,n,k,s)
#endif
          end do

          if ( SYStype == 1 ) then
             call Fock_cg( n1,n2,k,k,trho,tvht,1 )
          else
             call Fock_fft(n1,n2,k,k,trho,tvht,1)
          end if

          c = alpha_hf*(2.0d0*occ_factor)*occ(m,k,s)
          do i=n1,n2
             hunk(i,n,k,s)=hunk(i,n,k,s)-c*tvht(i)*unk(i,m,k,s)
          end do

          if ( m == n ) cycle

          c = alpha_hf*(2.0d0*occ_factor)*occ(n,k,s)
          do i=n1,n2
#ifdef _DRSDFT_
             hunk(i,m,k,s)=hunk(i,m,k,s)-c*tvht(i)*unk(i,n,k,s)
#else
             hunk(i,m,k,s)=hunk(i,m,k,s)-c*conjg(tvht(i))*unk(i,n,k,s)
#endif
          end do

       end do ! m

    end do ! n

! --- unoccupied orbitals

    do n=MB_0,MB_1

       if ( abs(occ(n,k,s)) >= 1.d-10 ) cycle

       do m=MB_0,MB_1

          if ( abs(occ(m,k,s)) < 1.d-10 ) cycle

          do i=n1,n2
#ifdef _DRSDFT_
             trho(i) = unk(i,m,k,s)*unk(i,n,k,s)
#else   
             trho(i) = conjg(unk(i,m,k,s))*unk(i,n,k,s)
#endif
          end do

          if ( SYStype == 1 ) then
             call Fock_cg( n1,n2,k,k,trho,tvht,1 )
          else
             call Fock_fft(n1,n2,k,k,trho,tvht,1)
          end if

          c = alpha_hf*(2.0d0*occ_factor)*occ(m,k,s)
          do i=n1,n2
             hunk(i,n,k,s)=hunk(i,n,k,s)-c*tvht(i)*unk(i,m,k,s)
          end do

       end do ! m

    end do ! n

    deallocate( tvht ) 
    deallocate( trho )

    return

  END SUBROUTINE Fock_2


  SUBROUTINE Fock_4( k,s,n1,n2 )
    implicit none
    integer,intent(IN) :: k,s,n1,n2
#ifdef _DRSDFT_
    real(8),allocatable :: trho(:),tvht(:)
#else
    complex(8),allocatable :: trho(:),tvht(:)
#endif
    real(8) :: c
    integer :: m,n,i,j,nwork,iwork,ierr
    integer,allocatable :: mapwork(:,:)

! ---

    nwork=0
    i=0
    do n=1,MB
       do m=1,n
          if ( abs(occ(n,k,s))<1.d-10 .and. abs(occ(m,k,s))<1.d-10 ) cycle
          i=i+1
          j=mod(i-1,np_band)
          if ( j == myrank_b ) nwork=nwork+1
       end do
    end do

    if ( disp_switch_parallel ) then
       write(*,*) "total # of me    =",i
       write(*,*) "# of me of rank0 =",nwork
    end if

    allocate( mapwork(2,nwork) ) ; mapwork=0

    nwork=0
    i=0
    do n=1,MB
       do m=1,n
          if ( abs(occ(n,k,s))<1.d-10 .and. abs(occ(m,k,s))<1.d-10 ) cycle
          i=i+1
          j=mod(i-1,np_band)
          if ( j == myrank_b ) then
             nwork=nwork+1
             mapwork(1,nwork)=m
             mapwork(2,nwork)=n
          end if
       end do
    end do

! ---

    allocate( trho(n1:n2) ) ; trho=zero
    allocate( tvht(n1:n2) ) ; tvht=zero

! ---

    do iwork=1,nwork

       m = mapwork(1,iwork)
       n = mapwork(2,iwork)

       do i=n1,n2
#ifdef _DRSDFT_
          trho(i) = unk(i,m,k,s)*unk(i,n,k,s)
#else   
          trho(i) = conjg(unk(i,m,k,s))*unk(i,n,k,s)
#endif
       end do

       if ( SYStype == 1 ) then
          call Fock_cg( n1,n2,k,k,trho,tvht,1 )
       else
          call Fock_fft( n1,n2,k,k,trho,tvht,1 )
       end if

       if ( abs(occ(m,k,s)) >= 1.d-10 ) then
          c = alpha_hf*(2.0d0*occ_factor)*occ(m,k,s)
          do i=n1,n2
             hunk(i,n,k,s)=hunk(i,n,k,s)-c*tvht(i)*unk(i,m,k,s)
          end do
       end if

       if ( m == n ) cycle

       if ( abs(occ(n,k,s)) >= 1.d-10 ) then
          c = alpha_hf*(2.0d0*occ_factor)*occ(n,k,s)
          do i=n1,n2
#ifdef _DRSDFT_
             hunk(i,m,k,s)=hunk(i,m,k,s)-c*tvht(i)*unk(i,n,k,s)
#else
             hunk(i,m,k,s)=hunk(i,m,k,s)-c*conjg(tvht(i))*unk(i,n,k,s)
#endif
          end do
       end if

    end do ! iwork

    deallocate( tvht ) 
    deallocate( trho )

    deallocate( mapwork )

! ---

    call mpi_allreduce( MPI_IN_PLACE,hunk(n1,1,k,s),MB*(n2-n1+1) &
                       ,TYPE_MAIN,MPI_SUM,comm_band,ierr )

    return

  END SUBROUTINE Fock_4


END MODULE fock_module
