module atomopt_ef_module

  use lattice_module
  use atom_module, only: atom, construct_atom, aa_atom &
                        ,write_coordinates_atom, shift_aa_coordinates_atom &
                        ,write_xyz_atom
  use force_module
  use pseudopot_module, only: pselect
  use eion_module
  use ps_local_module
  use ps_local_mol_module
  use ps_pcc_mol_module
  use ps_nloc2_mol_module
  use strfac_module
  use ps_pcc_module
  use ps_nloc3_module
  use ps_nloc2_module
  use ps_nloc_mr_module
  use scf_module
  use atomopt_diis_module, only: calc_coef_diis
  use atomopt_io_module, only: flag_continue_atomopt &
                             , read_atomopt_io, write_atomopt_io

  implicit none

  private
  public :: atomopt_ef

  logical :: disp_sw, disp_scf
  integer :: SYStype
  integer :: NiterSCF

contains


  subroutine atomopt_ef( SYStype_in, fmax_tol, ncycle, okstep_in, max_linmin_in, max_alpha_in, NiterSCF_in )

    implicit none
    integer,intent(in) :: SYStype_in
    real(8),intent(in) :: fmax_tol
    integer,intent(in) :: ncycle
    real(8),intent(in) :: okstep_in
    integer,intent(in) :: max_linmin_in
    real(8),intent(in) :: max_alpha_in
    integer,optional,intent(in) :: NiterSCF_in
    type(atom) :: ion
    type(lattice) :: aa, bb
    integer :: max_loop, max_linmin, linmin
    integer :: ishape(1), ishape2(2), i1,i2, LWORK=0
    integer :: n,il,iu,m,a,ierr,loop,i,j,ip,loop_start
    integer,allocatable :: iwork(:),ifail(:)
    real(8) :: etot0, etot, fmax
    real(8) :: dxdg,dxHdx,c1,c2,c,dmax,dtmp
    real(8) :: vl,vu,tol,alpha,okstep,max_alpha
    real(8) :: aa_inv(3,3),da(3),da_tmp(3)
    real(8),parameter :: one=1.0d0, zero=0.0d0
    real(8),allocatable :: g(:),x(:),Hessian(:,:),Htmp(:,:)
    real(8),allocatable :: Vtmp(:,:),Wtmp(:,:)
    real(8),allocatable :: history(:,:),g0(:),x0(:),d(:)
    real(8),allocatable :: dx(:),dg(:),Hdx(:)
    real(8),allocatable :: w(:),z(:,:),work(:)
    real(8),allocatable :: info_linmin(:), xyzf_linmin(:,:,:)
    real(8),parameter :: eig_threshold=0.02d0

    integer :: ndiis, mdiis
    real(8),allocatable :: xdiis(:,:), ediis(:,:), coef_diis(:)
    real(8),allocatable :: xtmp(:),etmp(:),gtmp(:),gdiis(:,:)
    logical :: flag_diis, flag_sd , flag_forced_sd
    real(8) :: alpha1,alpha2,alpha3,alpha4,etot1,etot2,etot3,etot4
    character(40) :: msg

    call write_border( 0, "atomopt_ef(start)" )
    call check_disp_switch( disp_sw, 0 )
    disp_scf = disp_sw
    call check_disp_length( i, 0 )
    if ( i < 2 ) then
       call check_disp_switch( .false., 1 )
       disp_scf = .false.
    end if

! ---

    SYStype = SYStype_in

    NiterSCF = 50 ; if ( present(NiterSCF_in) ) NiterSCF=NiterSCF_in

    max_loop = ncycle

    loop_start = 1

    okstep = okstep_in

    ndiis = 0
    if ( disp_sw .and. ndiis > 0 ) write(*,*) "DIIS is used: ndiis=",ndiis
    mdiis = 0

    max_linmin = max_linmin_in

    max_alpha = max_alpha_in

! ---

    call get_aa_lattice( aa )
    call get_inverse_lattice( aa%LatticeVector, aa_inv )

    call construct_atom( ion )

    do a=1,ion%natom
       ion%xyz(1:3,a) = matmul( aa%LatticeVector(1:3,1:3), ion%aaa(1:3,a) )
    end do

    if ( .not.flag_continue_atomopt() ) then

      if ( disp_sw ) then
        write(*,*) "Initial configuration"
        do a=1,ion%natom
          write(*,'(1x,3f20.15)') ion%aaa(1:3,a)
        end do
      end if

      call scf( etot, ierr ); if ( ierr  == -1 ) goto 999
      call calc_force( ion%natom, ion%force, fmax )

      if ( fmax <= fmax_tol ) goto 900

   end if

! ---

    n = 3*ion%natom
    allocate( g(n)  ) ; g=0.0d0
    allocate( x(n)  ) ; x=0.0d0
    allocate( d(n)  ) ; d=0.0d0
    allocate( g0(n) ) ; g0=0.0d0
    allocate( x0(n) ) ; x0=0.0d0
    allocate( Hessian(n,n) ) ; Hessian=0.0d0
    allocate( Htmp(n,n) ) ; Htmp=0.0d0
    allocate( Vtmp(n,n) ) ; Vtmp=0.0d0
    allocate( Hdx(n)    ) ; Hdx=0.0d0
    allocate( dx(n)     ) ; dx=0.0d0
    allocate( dg(n)     ) ; dg=0.0d0

    ishape(1) = n
    ishape2(1:2) = (/ 3, ion%natom /)

    allocate( history(6,0:max_loop) ) ; history=0.0d0

    allocate( info_linmin(size(history,1)) ); info_linmin=0.0d0
    allocate( xyzf_linmin(3,ion%natom,2) ); xyzf_linmin=0.0d0

    if ( flag_continue_atomopt() ) then

      call read_atomopt_io( &
           loop_start, &
           history, &
           x, x0, g, g0, &
           Hessian )

    else

      history(1,0) = etot
      history(2,0) = fmax
      history(3,0) = ierr ; if (ierr == -2) history(3,0)=NiterSCF
      history(4,0) = sum( history(3,0:0) )
      history(5:,0) = 0.0d0

    end if

! --- DIIS

    if ( ndiis > 0 ) then
      allocate( xdiis(n,ndiis)   ); xdiis=0.0d0
      allocate( ediis(n,ndiis)   ); ediis=0.0d0
      allocate( gdiis(n,ndiis)   ); gdiis=0.0d0
      allocate( coef_diis(ndiis) ); coef_diis=0.0d0
      allocate( xtmp(n) ); xtmp=0.0d0
      allocate( etmp(n) ); etmp=0.0d0
      allocate( gtmp(n) ); gtmp=0.0d0
    end if

! --- LAPACK

    if ( LWORK == 0 ) then
      allocate( w(n) ); w=0.0d0
      allocate( work(1) )
      call dsyev('V','U',n+1,Htmp,n+1,w,work,-1,ierr)
      LWORK=nint( work(1) )
      deallocate( work )
      allocate( work(LWORK) ); work=0.0d0
    end if

! ----------------------------------- loop

    do loop = loop_start, max_loop

      if ( disp_sw ) write(*,'(a60," loop=",i4)') repeat("-",60),loop

      alpha = 1.0d0
      flag_diis = .false.
      flag_sd = .false.
      flag_forced_sd = .false.

! ---

      call write_coordinates_atom( 197, 3 )
      call write_atomopt_io( loop, history(:,0:loop-1), &
                             x, x0, g, g0, Hessian )
! ---

      if ( loop == 1 ) then

        flag_sd = .true.

        Hessian=0.0d0
        do i=1,n
          Hessian(i,i) = one
        end do

        x(:) = reshape( ion%xyz(:,:)  , ishape )
        g(:) = reshape(-ion%force(:,:), ishape )
        d(:) = -g(:)

      else

        dx(:) = x(:) - x0(:)
        dg(:) = g(:) - g0(:)

        dxdg = sum( dx*dg )
        if ( disp_sw ) write(*,*) "dxdg=",dxdg

! ---

        if ( .false. ) then
        !if ( loop >= 3 ) then
          etot1 = history(1,loop-1)
          etot2 = history(1,loop-2)
          etot3 = history(1,loop-3)
          if ( etot1 > etot2 .and. etot2 > etot3 ) then
            if ( disp_sw ) write(*,*) "Climbing PES (SD is applied)"
            flag_forced_sd = .true.
          end if
          open(297,file='trajectory_ef.xyz',status='old')
          do j=1,loop-4
            read(297,*)
            read(297,*)
            do i=1,size(ion%xyz,2)
              read(297,*)
            end do
            read(297,*)
            do i=1,size(ion%xyz,2)
              read(297,*)
            end do
          end do
          read(297,*) n
          read(297,*) msg
          if ( disp_sw ) then
            write(*,*) "label, natom=",msg, n
            write(*,*) "etot(loop-3)=",history(1,loop-3)
            write(*,*) "etot(loop-2)=",etot2
            write(*,*) "etot(loop-1)=",etot1
          end if
          do i=1,size(ion%xyz,2)
            read(297,*) ion%xyz(:,i)
          end do
          read(297,*)
          do i=1,size(ion%force,2)
            read(297,*) ion%force(:,i)
          end do
          close(297)
          do i=1,size(ion%xyz,2)
            i2 = 3*i
            i1 = i2 - 3 + 1
            x(i1:i2) = ion%xyz(:,i)
            g(i1:i2) =-ion%force(:,i)
          end do
        end if

! ---

        if ( dxdg <= 0.0d0 .or. flag_forced_sd ) then

          if ( disp_sw ) write(*,*) "Steepest descent (Restart EF-opt process)"

          flag_sd = .true.
          flag_forced_sd = .false.

          d(:)  =-g(:)
          x0(:) = x(:)
          g0(:) = g(:)

          Hessian=0.0d0
          do i=1,size(Hessian,1)
            Hessian(i,i)=1.0d0
          end do

        else

          flag_sd = .false.

          call dgemv( 'N', n, n, one, Hessian, n, dx, 1, zero, Hdx, 1 )
          dxHdx = sum( dx*Hdx )
          c1 = 1.0d0/dxdg
          c2 = 1.0d0/dxHdx
          do j=1,n
          do i=1,n
            Hessian(i,j) = Hessian(i,j) + dg(i)*dg(j)*c1 - Hdx(i)*Hdx(j)*c2
          end do
          end do

          Htmp(:,:) = Hessian(:,:)
          call dsyev('V','U',n,Htmp,n,w,work,size(work),ierr)

          do i=1,n
            if ( w(i) < eig_threshold ) then
              if ( disp_sw ) write(*,*) "i,w(i)",i,w(i),"  ---> replaced to",eig_threshold
              w(i) = eig_threshold
            else
              exit
            end if
          end do

          Vtmp=0.0d0
          do i=1,n
            Vtmp(i,i)=1.0d0/w(i)
          end do
          Vtmp=matmul( Vtmp,transpose(Htmp) )
          Vtmp=matmul( Htmp,Vtmp )

! --- DIIS

          if ( ndiis > 0 ) then
            mdiis = min( mdiis+1, ndiis )
            do i=mdiis,2,-1
              xdiis(:,i) = xdiis(:,i-1)
              ediis(:,i) = ediis(:,i-1)
              gdiis(:,i) = gdiis(:,i-1)
            end do
            xdiis(:,1) = x(:)
            ediis(:,1) = x(:)-x0(:)
            gdiis(:,1) = g(:)
            if ( mdiis > 1 .or. mdiis == ndiis ) then
              call calc_coef_diis( coef_diis(1:mdiis), ediis(:,1:mdiis) )
              xtmp = matmul( xdiis(:,1:mdiis), coef_diis(1:mdiis) )
              etmp = matmul( ediis(:,1:mdiis), coef_diis(1:mdiis) )
              gtmp = matmul( gdiis(:,1:mdiis), coef_diis(1:mdiis) )
              flag_diis = .true.
            end if
            !dmax=0.0d0
            !do a=1,ion%natom
            !  i2 = 3*a
            !  i1 = i2 - 3 + 1
            !  dtmp = sqrt(sum((xtmp(i1:i2)-x0(i1:i2))**2))
            !  dmax = max(dmax,dtmp)
            !end do
            !write(*,*) "Maximum displacement(DIIS)",dmax
          end if

          if ( flag_diis ) then
            call DGEMV('N',n,n,-1.0d0,Vtmp,n,gtmp(:),1,0.0d0,d,1)
          else
            call DGEMV('N',n,n,-1.0d0,Vtmp,n,g(:),1,0.0d0,d,1)
          end if

        end if

      end if

! ---

      x0(:) = x(:)
      g0(:) = g(:)

! ---

      do a=1,ion%natom
        i2 = a*3
        i1 = i2 - 3 + 1 
        da = matmul( aa_inv, d(i1:i2) )
        do i=1,3
          da_tmp(1) = abs(da(i))
          da_tmp(2) = abs(da(i)+1.0d0)
          da_tmp(3) = abs(da(i)-1.0d0)
          j = minloc( da_tmp, 1 )
          select case(j)
          case(1)
          case(2); da(i)=da(i)+1.0d0
          case(3); da(i)=da(i)-1.0d0
          end select
        end do
        d(i1:i2) = matmul( aa%LatticeVector, da )
      end do

! ---

      info_linmin=1.0d100
      xyzf_linmin=0.0d0
      alpha1=0.0d0; alpha2=0.0d0; alpha3=0.0d0; alpha4=0.0d0
      etot1 =0.0d0; etot2 =0.0d0; etot3 =0.0d0; etot4 =0.0d0

      do linmin = 1, max_linmin !---------- Line Minimization

        select case(linmin)
        case( 1 )
          alpha  = 1.0d0
          alpha1 = alpha
        case(2)
          alpha  = (max_alpha-1.0d0)*0.3d0
          alpha2 = alpha
        case(3)
          alpha  = max_alpha
          alpha3 = alpha
        case(4)
          if ( etot1 >= etot2 .and. etot2 <= etot3 ) then
            alpha  = alpha1 + (alpha3-alpha2)
            alpha4 = alpha
         else if ( etot1 <= etot2 .and. etot1 <= etot3 ) then
            alpha = alpha1*0.3d0
            alpha4=alpha1 ; etot4=etot1
            alpha1=alpha  ; etot1=0.0d0 
          else if ( etot3 <= etot2 .and. etot3 <= etot1 ) then
            alpha = alpha3*1.7d0
            alpha4=alpha3; etot4=etot3
            alpha3=alpha ; etot3=0.0d0
          else
            write(*,'("alpha1,apha2,alpha3,alpha4",4f10.5)') alpha1,alpha2,alpha3,alpha4
            write(*,'("etot1,apha2,etot3,etot4",4f10.5)') etot1,etot2,etot3,etot4
            call stop_program('zzz')
          end if
        case(5:)
          
        end select

        dmax=0.0d0
        do a=1,ion%natom
          i2 = 3*a
          i1 = i2 - 3 + 1
          dtmp = sqrt(sum(d(i1:i2)**2))*alpha
          dmax = max(dmax,dtmp)
        end do
        !if ( disp_sw ) then
        !  write(*,*) "Maximum displacement(bohr):",dmax
        !end if
        if ( dmax > okstep ) then
          alpha=alpha*okstep/dmax
          !if ( disp_sw ) then
          !  write(*,*) "Maxmimum displacement is limited to",okstep
          !  write(*,*) "alpha is changed: alpha=",alpha
          !end if
        end if

! ---

        if ( flag_diis ) then
          do a=1,ion%natom
            i2 = 3*a
            i1 = i2 - 3 + 1
            ion%xyz(:,a) = xtmp(i1:i2) + alpha*d(i1:i2)
          end do
        else
          do a=1,ion%natom
            i2 = 3*a
            i1 = i2 - 3 + 1
            ion%xyz(:,a) = x0(i1:i2) + alpha*d(i1:i2)
          end do
        end if

! ---

        aa_atom(:,:) = matmul( aa_inv, ion%xyz )
        call shift_aa_coordinates_atom( aa_atom )        

! ---

        !if ( disp_sw ) then
        !  write(*,*) "Next trial configuration"
        !end if
        dmax=0.0d0
        do a=1,ion%natom
          i2 = 3*a
          i1 = i2 - 3 + 1
          dtmp = sqrt(sum(d(i1:i2)**2))*alpha
          !if ( disp_sw ) then
          !  write(*,'(i4,2x,3f10.5,2x,3es14.5,2x,es14.5)') &
          !       a,aa_atom(:,a),ion%xyz(:,a),dtmp
          !end if
          dmax=max(dmax,dtmp)
        end do
        !if ( disp_sw ) then
        !  write(*,*) "Maximum displacement(bohr):",dmax
        !end if

        call write_coordinates_atom( 97, 3 )

        call scf( etot, ierr ); if ( ierr == -1 ) goto 999
        call calc_force( ion%natom, ion%force, fmax )

        write(msg,*) loop, etot
        call write_trajectory( ion%xyz, ion%force, msg )

        history(1,loop) = etot
        history(2,loop) = fmax
        history(3,loop) = ierr ; if (ierr == -2) history(3,loop)=NiterSCF
        history(4,loop) = sum( history(3,0:loop) )
        history(5,loop) = alpha
!        c=0.0d0
!        do a=1,ion%natom
!          i2=3*a
!          i1=i2-3+1
!          c = c - sum(d(i1:i1)*ion%force(:,a))
!        end do
        history(6,loop) = sum(d*g)

        if ( disp_sw ) then
          do i=loop,loop
            write(*,'("linmin ",i4,f20.10,es14.5,i4,i6,2es14.5)') &
                 i, history(1:2,i), nint(history(3:4,i)),history(5:6,i)
          end do
        end if

        if ( etot < info_linmin(1) ) then
          info_linmin(1:6) = history(1:6,loop)
          xyzf_linmin(:,:,1) = ion%xyz
          xyzf_linmin(:,:,2) = ion%force
        end if

        select case(linmin)
        case(1); etot1=etot
        case(2); etot2=etot
        case(3); etot3=etot
        end select

        if ( linmin >= 4 ) then
          if ( etot1 == 0.0d0 ) then
            etot1=etot
          else if ( etot3 == 0.0d0 ) then
            etot3=etot
          else if ( etot4 == 0.0d0 ) then
            etot4=etot
          end if
        end if

        !write(*,'("alpha1,alpha2,alpha3,alpha4",4f12.7)') alpha1,alpha2,alpha3,alpha4
        !write(*,'("etot1 ,etot2 ,etot3 ,etot4 ",4f12.7)') etot1,etot2,etot3,etot4

        if ( .not.flag_sd .or. fmax <= fmax_tol ) exit

      end do !linmin

      history(:,loop) = info_linmin(:)
      fmax = info_linmin(2)
      ion%xyz = xyzf_linmin(:,:,1)
      ion%force = xyzf_linmin(:,:,2)

      if ( disp_sw ) then
        do i=0,loop
          write(*,'("History",i4,f20.10,es14.5,i4,i6,2es14.5)') &
               i, history(1:2,i), nint(history(3:4,i)),history(5:6,i)
        end do
      end if

      if ( fmax <= fmax_tol ) exit

      x(:) =  reshape( ion%xyz(:,:)  , ishape )
      g(:) = -reshape( ion%force(:,:), ishape )

    end do ! loop

! ---

900 if ( disp_sw ) then
       write(*,'(1x,"etot    :",f25.15)') etot
       write(*,'(1x,"fmax/tol:",es12.5," /",es12.5)') fmax,fmax_tol
    end if

999 call check_disp_switch( disp_sw, 1 )
    call write_border( 0, "atomopt_ef(end)" )

    deallocate( work )
    deallocate( w )
    deallocate( history )
    deallocate( dg )
    deallocate( dx )
    deallocate( Hdx )
    deallocate( Htmp )
    deallocate( Hessian )
    deallocate( x0 )
    deallocate( g0 )
    deallocate( x )
    deallocate( g )

  end subroutine atomopt_ef


  subroutine scf( etot, ierr_out )
    implicit none
    real(8),intent(out) :: etot
    integer,intent(out) :: ierr_out

    select case(SYStype)
    case default

       call calc_eion

       call construct_strfac
       call construct_ps_local
       call construct_ps_pcc
       call destruct_strfac

       select case(pselect)
       case(2)
          call prep_ps_nloc2
       case(3)
          call prep_ps_nloc3
       case(5)
          call prep_ps_nloc_mr
       end select

    case(1)

       call calc_eion

       call construct_ps_local_mol
       call construct_ps_pcc_mol
       call prep_ps_nloc2_mol

    end select

    call calc_scf( ierr_out, NiterSCF, Etot_out=etot )

  end subroutine scf


  subroutine write_trajectory( xyz, force, msg )
    implicit none
    real(8),intent(in) :: xyz(:,:), force(:,:)
    character(*),intent(in) :: msg
    integer,parameter :: u=297
    integer :: i, myrank
    include 'mpif.h'
    call MPI_Comm_rank(MPI_COMM_WORLD,myrank,i)
    if ( myrank == 0 ) then
      !
      open(u,file='trajectory_ef.xyz',position='append')
      call write_xyz_atom( u, xyz, "xyz_id_etot :"//msg )
      close(u)
      !
      open(u,file='trajectory_ef.force',position='append')
      write(u,*) size(force,2)
      write(u,*) "force_id_etot:",msg
      do i=1,size(force,2)
        write(u,*) force(:,i)
      end do
      close(u)
      !
    end if
  end subroutine write_trajectory


end module atomopt_ef_module
