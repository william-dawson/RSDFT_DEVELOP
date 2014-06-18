MODULE test_force_module

  use watch_module
  use parallel_module
  use atom_module

  use ps_local_module
  use force_ewald_module
  use ps_nloc2_module

  use force_local_mol_module
  use force_ion_mol_module
  use force_nloc2_mol_module

  implicit none

  PRIVATE
  PUBLIC :: test_force

  logical :: disp_switch

CONTAINS


  SUBROUTINE test_force(systype)
    implicit none
    integer,intent(IN) :: systype

    disp_switch = ( myrank == 0 )

    select case(systype)
    case default
       if ( disp_switch ) write(*,'(a60,"test_force(solid)")') repeat("-",60)
       call test_force_sol
    case(1)
       if ( disp_switch ) write(*,'(a60,"test_force(mol)")') repeat("-",60)
       call test_force_mol
    end select

  END SUBROUTINE test_force


  SUBROUTINE test_force_sol
    implicit none
    real(8),allocatable :: force(:,:),forcet(:,:)
    integer :: i

    allocate( force(3,Natom)  ) ; force=0.d0
    allocate( forcet(3,Natom) ) ; forcet=0.d0

    call watcht(disp_switch,"floc",0)
    call calc_force_ps_local(Natom,force)
    call watcht(disp_switch,"floc",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    call watcht(disp_switch,"fewl",0)
    call calc_force_ewald(Natom,force)
    call watcht(disp_switch,"fewl",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    call watcht(disp_switch,"fnlc",0)
    call calc_force_ps_nloc2(Natom,force)
    call watcht(disp_switch,"fnlc",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    if ( disp_switch ) then
       write(*,*) "ftot"
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,forcet(1:3,i),myrank
       end do
    end if

    deallocate( forcet )
    deallocate( force  )

  END SUBROUTINE test_force_sol


  SUBROUTINE test_force_mol
    implicit none
    real(8),allocatable :: force(:,:),forcet(:,:)
    integer :: i

    allocate( force(3,Natom)  ) ; force=0.d0
    allocate( forcet(3,Natom) ) ; forcet=0.d0

    call watcht(disp_switch,"floc",0)
    call calc_force_local_mol(force)
    call watcht(disp_switch,"floc",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    call watcht(disp_switch,"fewl",0)
    call calc_force_ion_mol(force)
    call watcht(disp_switch,"fewl",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    call watcht(disp_switch,"fnlc",0)
    call calc_force_nloc2_mol(force)
    call watcht(disp_switch,"fnlc",1)
    forcet(:,:)=forcet(:,:)+force(:,:)

    if ( disp_switch ) then
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
       end do
    end if

    if ( disp_switch ) then
       write(*,*) "ftot"
       do i=1,Natom
          write(*,'(1x,i6,3g20.10,i6)') i,forcet(1:3,i),myrank
       end do
    end if

    deallocate( forcet )
    deallocate( force  )

  END SUBROUTINE test_force_mol


END MODULE test_force_module
