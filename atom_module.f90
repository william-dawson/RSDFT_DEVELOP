MODULE atom_module

  implicit none

  PRIVATE
  PUBLIC :: Natom,Nelement,aa_atom,ki_atom,zn_atom,md_atom,read_atom &
           ,atom_format

  integer :: Natom, Nelement
  integer,allocatable :: ki_atom(:), zn_atom(:), md_atom(:)
  real(8),allocatable :: aa_atom(:,:)
  integer :: atom_format

CONTAINS

  SUBROUTINE read_atom(rank,unit,ax,aa)
    implicit none
    integer,intent(IN) :: rank,unit
    real(8),intent(INOUT) :: ax,aa(3,3)
    integer :: i,iflag_latvec,idummy(10)
    character(3) :: cbuf,ckey
    ax=0.0d0
    aa=0.0d0
    idummy=0
    atom_format=0
    iflag_latvec=0
    if ( rank == 0 ) then
       rewind unit
       do i=1,10000
          read(unit,*,END=999) cbuf
          call convert_capital(cbuf,ckey)
          if ( ckey(1:2) == "AX" ) then
             backspace(unit)
             read(unit,*) cbuf,ax
             iflag_latvec=1
          else if ( ckey(1:2) == "A1" ) then
             backspace(unit)
             read(unit,*) cbuf,aa(1:3,1)
             iflag_latvec=1
          else if ( ckey(1:2) == "A2" ) then
             backspace(unit)
             read(unit,*) cbuf,aa(1:3,2)
             iflag_latvec=1
          else if ( ckey(1:2) == "A3" ) then
             backspace(unit)
             read(unit,*) cbuf,aa(1:3,3)
             iflag_latvec=1
          else if ( ckey(1:3) == "XYZ" ) then
             atom_format=2
             exit
          else if ( ckey(1:2) == "AA" ) then
             atom_format=1
             exit
          end if
       end do
999    continue
       if ( iflag_latvec == 0 .and. atom_format == 0 ) then
          rewind unit
       else if ( iflag_latvec == 1 ) then
          write(*,*) "ax=",ax
          write(*,'(1x,"a1=",3f20.15)') aa(1:3,1)
          write(*,'(1x,"a2=",3f20.15)') aa(1:3,2)
          write(*,'(1x,"a3=",3f20.15)') aa(1:3,3)
       end if
       if ( atom_format == 0 .or. atom_format == 1 ) then
          write(*,*) "Lattice coordinates are assumed"
          atom_format=1
       else if ( atom_format == 2 ) then
          write(*,*) "XYZ coordinates are assumed"
       end if
       read(unit,*) Nelement,Natom, idummy(1:Nelement)
       write(*,*) "Nelment,Natom=",Nelement,Natom
       allocate( zn_atom(Nelement) ) ; zn_atom=0
       zn_atom(1:Nelement) = idummy(1:Nelement)
       write(*,*) "zn_atom=",zn_atom(:)
    end if
    call send_atom_1(0,ax,aa)
    allocate( aa_atom(3,Natom) ) ; aa_atom=0.d0
    allocate( ki_atom(Natom)   ) ; ki_atom=0
    allocate( md_atom(Natom)   ) ; md_atom=0
    if ( .not.allocated(zn_atom) ) then
       allocate( zn_atom(Nelement) ) ; zn_atom=0
    end if
    if ( rank == 0 ) then
       do i=1,Natom
          read(unit,*) ki_atom(i),aa_atom(1:3,i),md_atom(i)
       end do
       write(*,'(8x,a7,3a18,2x,a7)') &
            "ki_atom","aa_atom1","aa_atom2","aa_atom3","md_atom"
       if ( Natom <= 11 ) then
          do i=1,Natom
             write(*,'(1x,i5,2x,i7,3f18.12,4x,i5)') &
                  i,ki_atom(i),aa_atom(:,i),md_atom(i)
          end do
       else
          do i=1,min(5,Natom)
             write(*,'(1x,i5,2x,i7,3f18.12,4x,i5)') &
                  i,ki_atom(i),aa_atom(:,i),md_atom(i)
          end do
          write(*,'(1x,10x,".")')
          write(*,'(1x,10x,".")')
          write(*,'(1x,10x,".")')
          do i=Natom-5,Natom
             write(*,'(1x,i5,2x,i7,3f18.12,4x,i5)') &
                  i,ki_atom(i),aa_atom(:,i),md_atom(i)
          end do
       end if
    end if
    call send_atom_2(0)
  END SUBROUTINE read_atom

  SUBROUTINE send_atom_1(myrank,ax,aa)
    implicit none
    integer,intent(IN) :: myrank
    real(8),intent(IN) :: ax,aa(3,3)
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(Natom,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(Nelement,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(ax,1,MPI_REAL8,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(aa,9,MPI_REAL8,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(atom_format,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
  END SUBROUTINE send_atom_1

  SUBROUTINE send_atom_2(myrank)
    implicit none
    integer,intent(IN) :: myrank
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(ki_atom,Natom,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(aa_atom,3*Natom,MPI_REAL8,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(zn_atom,Nelement,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
    call mpi_bcast(md_atom,Natom,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
  END SUBROUTINE send_atom_2

END MODULE atom_module
