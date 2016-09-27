MODULE bz_module

  use io_tools_module
  use symmetry_module, only: isymmetry, nsym, rgb

  implicit none

  PRIVATE
  PUBLIC :: generate_bz
  PUBLIC :: read_bz
  PUBLIC :: bzinfo
  PUBLIC :: construct_bzinfo_bz
  PUBLIC :: write_info_bz
  PUBLIC :: read_from_file_bz

  integer,PUBLIC :: Nbzsm
  integer,PUBLIC :: MMBZ
  real(8),allocatable,PUBLIC :: kbb(:,:)
  real(8),allocatable,PUBLIC :: weight_bz(:)

  integer :: nk
  integer :: mmm(3,2)
  integer :: npbz
  integer :: ndata_read_k=0
  real(8) :: kbb0(3)
  data kbb0/0.d0,0.d0,0.d0/
  integer :: use_inversion=1

  TYPE bzinfo
     integer :: nk
     integer :: n_irwedge, n_whole
     integer :: indx_range(2,3)
     integer,allocatable :: kgrid(:,:,:)
     integer,allocatable :: kpt(:,:)
     real(8),allocatable :: weight(:)
  END type bzinfo

  type(bzinfo) :: bz_master

  integer :: unit_out=20, unit_in=21
  character(16) :: file_out="bz_info"
  character(16) :: file_in=""

CONTAINS


  SUBROUTINE read_bz
    implicit none
    nk=0
    mmm(1:3,1)=(/ 0,0,0 /)
    mmm(1:3,2)=(/ 0,0,0 /)
    ndata_read_k=0
    kbb0(1:3)=0.0d0
    npbz=0
    use_inversion=1
    call IOTools_readStringKeyword( "FILEBZ", file_in )
    call IOTools_readIntegerKeyword( "NK", nk )
    call IOTools_readIntegerKeyword( "MMM1", mmm(:,1) )
    call IOTools_readIntegerKeyword( "MMM2", mmm(:,2) )
    call IOTools_readIntegerKeyword( "NPBZ", npbz )
    call IOTools_readIntegerKeyword( "INVBZ", use_inversion )
  END SUBROUTINE read_bz


  SUBROUTINE generate_bz
    implicit none
    logical :: disp_switch
    integer :: i,k,k1,iw,iw0,iw1,m1,m2,m3,mm1,mm2,mm3,i1,i2,i3,p1(3),p2(3)
    integer,allocatable :: mm(:,:),m(:,:),w(:),map(:)

    call write_border( 0," generate_bz(start)" )

    if ( file_in /= "" ) then

       call read_from_file_bz( file_in, kbb, weight_bz, nk, Nbzsm, MMBZ )

       allocate( m(3,Nbzsm) ) ; m=0
       allocate( mm(3,MMBZ) ) ; mm=0
       allocate( map(MMBZ)  ) ; map=0

    else 

       if ( nk <= 0 ) then

          if ( all(mmm(:,1)==0) ) then
             call write_string( "gamma point sampling is assumed" )
             nk=2
             mmm(:,1)=(/ 2,2,2 /)
             mmm(:,2)=(/ 2,2,2 /)
          else
             call Monkhorst_Pack( nk, mmm )
          end if

       end if

       if ( isymmetry > 0 ) then

          call generate_bz_sym( m, mm, map )

       else

          m1 =mmm(1,1) ; m2 =mmm(2,1) ; m3 =mmm(3,1)
          mm1=mmm(1,2) ; mm2=mmm(2,2) ; mm3=mmm(3,2)

          k=(2*m1+1)*(2*m2+1)*(2*m3+1)*2
          allocate( mm(3,k),m(3,k),w(k),map(k) )
          mm=0 ; m=0 ; w=0 ; map=0
          k=0 ; k1=0

          iw1= 1
          iw0=-1 ; if ( use_inversion < 1 ) iw0=1

          do i1=-m1,m1,mm1
          do i2=-m2,m2,mm2
          loop_A : do i3=-m3,m3,mm3

             do iw=iw1,iw0,-2

                p1(1)=i1*iw ; p1(2)=i2*iw ; p1(3)=i3*iw ; p2(1:3)=p1(1:3)
                do i=1,3
                   p1(i)=mod(p2(i),nk)
                   if ( p1(i)>  nk/2 ) p1(i)=p1(i)-nk
                   if ( p1(i)<=-nk/2 ) p1(i)=p1(i)+nk
                end do
                if ( k1 > 0 ) then
                   do i=1,k1
                      if ( mm(1,i)==p1(1) .and. &
                           mm(2,i)==p1(2) .and. &
                           mm(3,i)==p1(3)         ) cycle loop_A
                   end do
                end if

                if ( iw == 1 ) then
                   k=k+1
                   m(1:3,k)=p1(1:3)
                   w(k)=1
                else
                   w(k)=2
                end if

                k1=k1+1
                mm(1:3,k1)=p1(1:3)
                map(k1)=k

             end do ! iw

          end do loop_A
          end do
          end do

          Nbzsm = k
          if ( npbz > k ) Nbzsm=npbz

          MMBZ  = k1

          allocate( weight_bz(Nbzsm) ) ; weight_bz=0.d0
          allocate( kbb(3,Nbzsm)     ) ; kbb=0.d0

          kbb(1:3,1:k)=real(m(1:3,1:k),8)/nk
          weight_bz(1:k)=real(w(1:k),8)/MMBZ

          if ( Nbzsm == ndata_read_k ) then
             kbb(1:3,1) = kbb0(1:3)
             ndata_read_k = 0
          end if

          deallocate( w )

       end if

    end if

    call construct_bzinfo_master &
         ( nk, Nbzsm, MMBZ, m, mm, map, weight_bz, bz_master )

    deallocate( map,m,mm )

    call check_disp_switch( disp_switch, 0 )
    if ( disp_switch ) then
       write(*,*) "Nbzsm, MMBZ =",Nbzsm,MMBZ
       write(*,'(1x,a4,a30,a12)') "","kbb","weight_bz"
       do k=1,Nbzsm
          write(*,'(1x,i4,3f10.5,f12.5)') k,kbb(:,k),weight_bz(k)
       end do
    end if

    call write_border( 0," generate_bz(end)" )

  END SUBROUTINE generate_bz


  SUBROUTINE generate_bz_sym( m, mm, map )
    implicit none
    integer,allocatable,intent(INOUT) :: m(:,:), mm(:,:), map(:)
    logical :: disp_switch
    integer,allocatable :: w(:),w1(:),w2(:)
    integer :: m1,m2,m3,mm1,mm2,mm3,i1,i2,i3,p1(3),p2(3)
    integer :: i,k,k1,iw,iw0,iw1,nkmax,p3(3),ns,ni,is,nni,ig
    real(8) :: c,tmp(3)

    call write_border( 0," generate_bz_sym(start)" )

    m1 =mmm(1,1) ; m2 =mmm(2,1) ; m3 =mmm(3,1)
    mm1=mmm(1,2) ; mm2=mmm(2,2) ; mm3=mmm(3,2)

    nkmax=(2*m1+1)*(2*m2+1)*(2*m3+1)*2
    allocate( mm(3,nkmax),m(3,nkmax),w(nkmax) ) ; mm=0 ; m=0 ; w=0
    allocate( map(nkmax) ) ; map=0
    allocate( w1(nkmax),w2(nkmax) ) ; w1=0 ; w2=0

    iw1= 1
    iw0=-1 ; if ( use_inversion < 1 ) iw0=1

    ni=1
    is=1

    do i1=-m1,m1,mm1
    do i2=-m2,m2,mm2
       loop_3 : do i3=-m3,m3,mm3

          p1(1)=i1 ; p1(2)=i2 ; p1(3)=i3 ; p2(1:3)=p1(1:3)

          do i=1,3
             p1(i)=mod(p2(i),nk)
             if ( p1(i) >   nk/2 ) p1(i)=p1(i)-nk
             if ( p1(i) <= -nk/2 ) p1(i)=p1(i)+nk
          end do

          do i=1,ni-1
             if ( all(p1(1:3)==mm(1:3,i)) ) cycle loop_3
          end do

          ns =0
          nni=ni

          do iw=iw1,iw0,-2
             loop_sym : do ig=1,nsym

                if ( ni>nkmax ) stop "generate_bz_sym(1)"

                tmp(:) = matmul( rgb(:,:,ig),p1(:) )*iw
                p3(:) = nint( tmp(:) )

                do i=1,3
                   p2(i)=mod(p3(i),nk)
                   if ( p2(i) >  nk/2 ) p2(i)=p2(i)-nk
                   if ( p2(i) <=-nk/2 ) p2(i)=p2(i)+nk
                end do

                do i=nni,ni-1
                   if ( all(p2(:)==mm(:,i)) ) cycle loop_sym
                end do
                ns=ns+1
                mm(:,ni)=p2(:)
                map(ni)=is
                ni=ni+1

             end do loop_sym
          end do ! iw

          w(is)=ns

          m(1:3,is)=mm(1:3,nni)

          is=is+1

       end do loop_3
    end do ! i2
    end do ! i1

    is=is-1
    ni=ni-1

    do k=1,ni
       w1(k)=1
       do i=1,3
          i1=mod(i,3)+1
          i2=mod(i+1,3)+1
          if ( abs(mm(i,k)) == nk/2 ) then
             do k1=1,ni
                if ( k == k1 ) cycle
                if ( mm(i ,k1) ==-mm(i ,k) .and. &
                     mm(i1,k1) == mm(i1,k) .and. &
                     mm(i2,k1) == mm(i2,k) ) w1(k)=w1(k)*2
             end do
          end if
       end do ! i
    end do ! k

    do k=1,is
       do k1=1,ni
          if ( all(m(1:3,k)==mm(1:3,k1)) ) then
             w2(k)=w1(k1)
             exit
          end if
       end do
    end do

    Nbzsm = is
    if ( npbz > is ) Nbzsm = npbz

    MMBZ = ni

    allocate( weight_bz(Nbzsm) ) ; weight_bz=0.0d0
    allocate( kbb(3,Nbzsm)     ) ; kbb=0.0d0

    do k=1,Nbzsm
       kbb(1:3,k)   = real( m(1:3,k), 8 )/real( nk, 8 )
       weight_bz(k) = real( w(k), 8 )/real( w2(k), 8 )
    end do

    c=sum( weight_bz(:) )
    weight_bz(:)=weight_bz(:)/c

    call check_disp_switch( disp_switch, 0 )
    if ( disp_switch ) then
       write(*,*) "sum(w)  =",sum(w),sum(w2),sum(w1)
       write(*,*) "sum(wbz)=",sum(weight_bz)
    end if

    deallocate( w2,w1,w )

    call write_border( 0," generate_bz_sym(end)" )

    return

  END SUBROUTINE generate_bz_sym


  SUBROUTINE construct_bzinfo_master( nk, n_ir, n_wh, m, mm, map, w, bz )
    implicit none
    integer,intent(IN) :: nk, n_ir, n_wh
    integer,intent(IN) :: m(3,n_ir), mm(3,n_wh), map(n_wh)
    real(8),intent(IN) :: w(n_ir)
    type(bzinfo),intent(INOUT) :: bz
    integer :: i,j
    bz%nk        = nk
    bz%n_irwedge = n_ir
    bz%n_whole   = n_wh
    do i=1,3
       bz%indx_range(1,i) = minval( mm(i,1:n_wh) )
       bz%indx_range(2,i) = maxval( mm(i,1:n_wh) )
    end do
    allocate( bz%kgrid(bz%indx_range(1,1):bz%indx_range(2,1) &
                      ,bz%indx_range(1,2):bz%indx_range(2,2) &
                      ,bz%indx_range(1,3):bz%indx_range(2,3)) ) ; bz%kgrid=0
    do i=1,n_wh
       bz%kgrid( mm(1,i),mm(2,i),mm(3,i) ) = map(i)
    end do
    allocate( bz%kpt(3,n_ir)  ) ; bz%kpt(:,:) = m(:,:)
    allocate( bz%weight(n_ir) ) ; bz%weight(:) = w(:)
  END SUBROUTINE construct_bzinfo_master


  SUBROUTINE construct_bzinfo_bz( bz )
    implicit none
    type(bzinfo),intent(INOUT) :: bz
    bz=bz_master
    return
!
! Allocatable arrays in derived-type variables are automatically allocated
! in Fortran2003 or later. The followings may work with older Fortran.
!
!    bz%nk        = bz_master%nk
!    bz%n_irwedge = bz_master%n_irwedge
!    bz%n_whole   = bz_master%n_whole
!    bz%indx_range(:,:) = bz_master%indx_range(:,:)
!    allocate( bz%kgrid(bz%indx_range(1,1):bz%indx_range(2,1) &
!                      ,bz%indx_range(1,2):bz%indx_range(2,2) &
!                      ,bz%indx_range(1,3):bz%indx_range(2,3)) ) ; bz%kgrid=0
!    bz%kgrid(:,:,:) = bz_master%kgrid(:,:,:)
!    allocate( bz%kpt(3,bz%n_irwedge)  ) ; bz%kpt(:,:) = bz_master%kpt(:,:)
!    allocate( bz%weight(bz%n_irwedge) ) ; bz%weight(:) = bz_master%weight(:)
  END SUBROUTINE construct_bzinfo_bz


  SUBROUTINE write_info_bz( b_vec, bz_in )

    implicit none
    real(8),intent(IN) :: b_vec(3,3)
    type(bzinfo),optional,intent(IN) :: bz_in
    integer :: k,k1,k2,k3,ir
    type(bzinfo) :: bz

    if ( file_in /= "" ) return

    if ( present(bz_in) ) then
       bz=bz_in
    else
       bz=bz_master
    end if

    open( unit_out, file=file_out )
    write(unit_out,'("Reciprocal lattice vectors")')
    write(unit_out,'(1x,3f22.15)') b_vec(1:3,1)
    write(unit_out,'(1x,3f22.15)') b_vec(1:3,2)
    write(unit_out,'(1x,3f22.15)') b_vec(1:3,3)
    write(unit_out,'("Number of division along a side            :",i4)') bz%nk
    write(unit_out,'("Number of k points in the irreducible wedge:",i4)') bz%n_irwedge
    write(unit_out,'("Number of k points in the whole BZ         :",i4)') bz%n_whole
    write(unit_out,'("Sampled k points")')
    write(unit_out,'(9x,3a4,a20)') "k1","k2","k3","weight"
    do k=1,bz%n_irwedge
       write(unit_out,'(1x,i6,2x,3i4,2x,3f20.15)') k,bz%kpt(1:3,k),bz%weight(k)
    end do
    write(unit_out,'("grid index range (k1):",2i4)') bz%indx_range(1:2,1)
    write(unit_out,'("grid index range (k2):",2i4)') bz%indx_range(1:2,2)
    write(unit_out,'("grid index range (k3):",2i4)') bz%indx_range(1:2,3)
    write(unit_out,'("k points in the whole BZ")')
    k=0
    do k3=bz%indx_range(1,3),bz%indx_range(2,3)
    do k2=bz%indx_range(1,2),bz%indx_range(2,2)
    do k1=bz%indx_range(1,1),bz%indx_range(2,1)
       ir=bz%kgrid(k1,k2,k3)
       if ( ir == 0 ) cycle
       k=k+1
       write(unit_out,'(1x,i6,2x,3i4,i6)') k,k1,k2,k3,ir
    end do
    end do
    end do
    close(unit_out)

  END SUBROUTINE write_info_bz


  SUBROUTINE read_from_file_bz( file, kbb, weight, nk, NBZsmp, NBZtot )

    implicit none
    character(*),intent(IN) :: file
    real(8),allocatable,intent(INOUT) :: kbb(:,:), weight(:)
    integer,intent(OUT) :: nk, NBZsmp, NBZtot
    integer :: k,mrnk
    character(32) :: cbuf
    include 'mpif.h'

    if ( file == "" ) return

    call write_border( 0, "read_form_file_bz(start)" )

    if ( allocated(kbb) ) deallocate(kbb)
    if ( allocated(weight_bz) ) deallocate(weight_bz)

    call MPI_COMM_RANK( MPI_COMM_WORLD, mrnk, k )

    if ( mrnk == 0 ) then

       open(unit_in,file=file,status="old")

       read(unit_in,'(a)') cbuf
       backspace(unit_in)

       if ( cbuf == "Reciprocal lattice vectors" ) then
          call read_info_bz( kbb, weight, nk, NBZsmp, NBZtot )
       else
          read(unit_in,*) NBZsmp
          allocate( kbb(3,NBZsmp) ) ; kbb=0.0d0
          do k=1,NBZsmp
             read(unit_in,*) kbb(:,k)
          end do
          allocate( weight(NBZsmp) ) ; weight=0.0d0
          nk=1
          NBZtot=NBZsmp
       end if

       close(unit_in)

    end if

    call MPI_BCAST( NBZsmp, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, k )
    call MPI_BCAST( nk    , 1, MPI_INTEGER, 0, MPI_COMM_WORLD, k )
    call MPI_BCAST( NBZtot, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, k )

    if ( .not.allocated(kbb) ) then
       allocate( kbb(3,NBZsmp) ) ; kbb=0.0d0
    end if
    if ( .not.allocated(weight) ) then
       allocate( weight(NBZsmp) ) ; weight=0.0d0
    end if

    call MPI_BCAST( kbb, size(kbb), MPI_REAL8, 0, MPI_COMM_WORLD, k )
    call MPI_BCAST( weight, size(weight), MPI_REAL8, 0, MPI_COMM_WORLD, k )

    kbb(:,:) = kbb(:,:)/dble(nk)

    call write_border( 0, "read_form_file_bz(end)" )

  END SUBROUTINE read_from_file_bz


  SUBROUTINE read_info_bz( kbb, weight, n_div, n_irwedge, n_whole )
    implicit none
    real(8),allocatable,intent(INOUT) :: kbb(:,:), weight(:)
    integer,intent(OUT) :: n_div, n_irwedge, n_whole
    character(80) :: cbuf
    integer :: i,k
    read(unit_in,*)
    read(unit_in,*)
    read(unit_in,*)
    read(unit_in,*)
    read(unit_in,'(a)') cbuf
    call get_num_from_chr( cbuf, n_div )
    read(unit_in,'(a)') cbuf
    call get_num_from_chr( cbuf, n_irwedge )
    read(unit_in,'(a)') cbuf
    call get_num_from_chr( cbuf, n_whole )
    read(unit_in,*)
    read(unit_in,*)
    if ( allocated(kbb) ) deallocate(kbb)
    allocate( kbb(3,n_irwedge) ) ; kbb=0.0d0
    if ( allocated(weight) ) deallocate(weight)
    allocate( weight(n_irwedge) ) ; weight=0.0d0
    do i=1,n_irwedge
       read(unit_in,*) k, kbb(1:3,i), weight(i)
    end do
  END SUBROUTINE read_info_bz


  SUBROUTINE get_num_from_chr( cbuf, n )
    implicit none
    character(*),intent(IN) :: cbuf
    integer,intent(OUT) :: n
    integer :: i
    do i=1,len_trim(cbuf)
       if ( cbuf(i:i) == ":" ) exit
    end do
    read(cbuf(i+1:),*) n
  END SUBROUTINE get_num_from_chr


  SUBROUTINE Monkhorst_Pack( n, m )
    implicit none
    integer,intent(INOUT) :: n, m(3,2)
    logical :: disp
    integer :: lcm_12, lcm
    call check_disp_switch( disp, 0 )
    if ( disp ) write(*,'(1x,"nk=",i5,"   ( MP mesh is used )")') n
! Least Common Multiplier
    lcm_12 = m(1,1)*m(2,1)/gcd( m(1,1),m(2,1) )
    n = lcm_12*m(3,1)/gcd( lcm_12,m(3,1) )
    n = n*2
    mmm(:,2) = n/mmm(:,1)
    mmm(:,1) = n/mmm(:,2)-1
    if ( disp ) then
       write(*,'(1x,"nk=",i5)') nk
       write(*,'(1x,"mmm1=",3i4)') mmm(:,1)
       write(*,'(1x,"mmm2=",3i4)') mmm(:,2)
    end if
  END SUBROUTINE Monkhorst_Pack


  FUNCTION gcd(m0,n0)
    implicit none
    integer :: gcd,m0,n0
    integer :: m,n,mtmp,loop

    if ( m0 >= n0 ) then
       m=m0
       n=n0
    else
       m=n0
       n=m0
    end if

    do loop=1,10000
       if ( n == 0 ) exit
       mtmp = n
       n = mod(m,n)
       m = mtmp
    end do

    gcd = m

  END FUNCTION gcd


END MODULE bz_module
