
! Copyright (C) 2002-2010 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.

!BOP
! !ROUTINE: gndstate
! !INTERFACE:
subroutine gndstate
! !USES:
use modmain
use modmpi
use modldapu
! !DESCRIPTION:
!   Computes the self-consistent Kohn-Sham ground-state. General information is
!   written to the file {\tt INFO.OUT}. First- and second-variational
!   eigenvalues, eigenvectors and occupancies are written to the unformatted
!   files {\tt EVALFV.OUT}, {\tt EVALSV.OUT}, {\tt EVECFV.OUT}, {\tt EVECSV.OUT}
!   and {\tt OCCSV.OUT}.
!
! !REVISION HISTORY:
!   Created October 2002 (JKD)
!   Added MPI, August 2010 (JKD)
!EOP
!BOC
implicit none
! local variables
logical exist
integer ik,is,ia
integer n,nwork,lp
real(8) dv,etp,de,timetot
! allocatable arrays
real(8), allocatable :: v(:)
real(8), allocatable :: work(:)
real(8), allocatable :: evalfv(:,:)
complex(8), allocatable :: evecfv(:,:,:)
complex(8), allocatable :: evecsv(:,:)
! require forces for structural optimisation
if ((task.eq.2).or.(task.eq.3)) tforce=.true.
! initialise global variables
call init0
call init1
! initialise OEP variables if required
if (xctype(1).lt.0) call init2
! only the MPI master process should write files
if (mp_mpi) then
! write the real and reciprocal lattice vectors to file
  call writelat
! write interatomic distances to file
  call writeiad(.false.)
! write symmetry matrices to file
  call writesym
! output the k-point set to file
  call writekpts
! write lattice vectors and atomic positions to file
  call writegeom(.false.)
! open INFO.OUT file
  open(60,file='INFO'//trim(filext),action='WRITE',form='FORMATTED')
! open TOTENERGY.OUT
  open(61,file='TOTENERGY'//trim(filext),action='WRITE',form='FORMATTED')
! open FERMIDOS.OUT
  open(62,file='FERMIDOS'//trim(filext),action='WRITE',form='FORMATTED')
! open MOMENT.OUT if required
  if (spinpol) open(63,file='MOMENT'//trim(filext),action='WRITE', &
   form='FORMATTED')
! open FORCEMAX.OUT if required
  if (tforce) open(64,file='FORCEMAX'//trim(filext),action='WRITE', &
   form='FORMATTED')
! open RMSDVEFF.OUT
  open(65,file='RMSDVEFF'//trim(filext),action='WRITE',form='FORMATTED')
! open DTOTENERGY.OUT
  open(66,file='DTOTENERGY'//trim(filext),action='WRITE',form='FORMATTED')
! open TENSMOM.OUT
  if (tmomlu) open(67,file='TENSMOM'//trim(filext),action='WRITE', &
   form='FORMATTED')
! write out general information to INFO.OUT
  call writeinfo(60)
  write(60,*)
end if
! initialise or read the charge density and potentials from file
iscl=0
if ((task.eq.1).or.(task.eq.3)) then
  call readstate
  if (mp_mpi) write(60,'("Potential read in from STATE.OUT")')
  if (autolinengy) call readfermi
else if (task.eq.200) then
  call phscveff
  if (mp_mpi) write(60,'("Supercell potential constructed from STATE.OUT")')
else
  call rhoinit
  call poteff
  call genveffig
  if (mp_mpi) write(60,'("Density and potential initialised from atomic data")')
end if
if (mp_mpi) call flushifc(60)
! size of mixing vector
n=lmmaxvr*nrmtmax*natmtot+ngrtot
if (spinpol) n=n+n*ndmag
if (ldapu.ne.0) n=n+2*lmmaxlu*lmmaxlu*nspinor*nspinor*natmtot
! allocate mixing arrays
allocate(v(n))
! determine the size of the mixer work array
nwork=-1
call mixerifc(mixtype,n,v,dv,nwork,v)
allocate(work(nwork))
10 continue
! set last self-consistent loop flag
tlast=.false.
etp=0.d0
! delete any existing eigenvector files
if ((task.eq.0).or.(task.eq.2)) call delevec
! begin the self-consistent loop
if (mp_mpi) then
  write(60,*)
  write(60,'("+------------------------------+")')
  write(60,'("| Self-consistent loop started |")')
  write(60,'("+------------------------------+")')
end if
do iscl=1,maxscl
  if (mp_mpi) then
    write(60,*)
    write(60,'("+--------------------+")')
    write(60,'("| Loop number : ",I4," |")') iscl
    write(60,'("+--------------------+")')
  end if
  if (iscl.ge.maxscl) then
    if (mp_mpi) then
      write(60,*)
      write(60,'("Reached self-consistent loops maximum")')
    end if
    tlast=.true.
  end if
  if (mp_mpi) call flushifc(60)
! generate the core wavefunctions and densities
  call gencore
! find the new linearisation energies
  call linengy
! write out the linearisation energies
  if (mp_mpi) call writelinen
! generate the APW radial functions
  call genapwfr
! generate the local-orbital radial functions
  call genlofr
! compute the overlap radial integrals
  call olprad
! compute the Hamiltonian radial integrals
  call hmlrad
! generate muffin-tin effective magnetic fields and s.o. coupling functions
  call genbeffmt
! begin parallel loop over k-points
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP PRIVATE(evalfv,evecfv,evecsv)
!$OMP DO
  do ik=1,nkpt
! distribute among MPI processes
    if (mod(ik-1,np_mpi).ne.lp_mpi) cycle
! every thread should allocate its own arrays
    allocate(evalfv(nstfv,nspnfv))
    allocate(evecfv(nmatmax,nstfv,nspnfv))
    allocate(evecsv(nstsv,nstsv))
! solve the first- and second-variational secular equations
    call seceqn(ik,evalfv,evecfv,evecsv)
! write the eigenvalues/vectors to file
    call putevalfv(ik,evalfv)
    call putevalsv(ik,evalsv(:,ik))
    call putevecfv(ik,evecfv)
    call putevecsv(ik,evecsv)
    deallocate(evalfv,evecfv,evecsv)
  end do
!$OMP END DO
!$OMP END PARALLEL
! broadcast eigenvalue array to every process
  do ik=1,nkpt
    lp=mod(ik-1,np_mpi)
    call mpi_bcast(evalsv(:,ik),nstsv,mpi_double_precision,lp,mpi_comm_world, &
     ierror)
  end do
! find the occupation numbers and Fermi energy
  call occupy
  if (autoswidth.and.mp_mpi) then
    write(60,*)
    write(60,'("New smearing width : ",G18.10)') swidth
  end if
  if (mp_mpi) then
! write the occupation numbers to file
    do ik=1,nkpt
      call putoccsv(ik,occsv(:,ik))
    end do
! write eigenvalues to file
    call writeeval
! write the Fermi energy to file
    call writefermi
  end if
! generate the density and magnetisation
  call rhomag
! LDA+U
  if (ldapu.ne.0) then
! generate the LDA+U density matrix
    call gendmatlu
! generate the LDA+U potential matrix
    call genvmatlu
! write the LDA+U matrices to file
    if (mp_mpi) call writeldapu
! calculate and write tensor moments to file
    if (tmomlu) call tensmom(67)
  end if
! compute the effective potential
  call poteff
! pack interstitial and muffin-tin effective potential and field into one array
  call mixpack(.true.,n,v)
! mix in the old potential and field with the new
  call mixerifc(mixtype,n,v,dv,nwork,work)
! unpack potential and field
  call mixpack(.false.,n,v)
! add the fixed spin moment effect field
  if (fixspin.ne.0) call fsmfield
! Fourier transform effective potential to G-space
  call genveffig
! reduce the external magnetic fields if required
  if (reducebf.lt.1.d0) then
    bfieldc(:)=bfieldc(:)*reducebf
    bfcmt(:,:,:)=bfcmt(:,:,:)*reducebf
  end if
! compute the energy components
  call energy
! output energy components
  if (mp_mpi) then
    call writeengy(60)
    write(60,*)
    write(60,'("Density of states at Fermi energy : ",G18.10)') fermidos
    write(60,'(" (states/Hartree/unit cell)")')
    write(60,'("Estimated band gap : ",G18.10)') bandgap
! write total energy to TOTENERGY.OUT and flush
    write(61,'(G22.12)') engytot
    call flushifc(61)
! write DOS at Fermi energy to FERMIDOS.OUT and flush
    write(62,'(G18.10)') fermidos
    call flushifc(62)
! output charges and moments
    call writechg(60)
! write total moment to MOMENT.OUT and flush
    if (spinpol) then
      write(63,'(3G18.10)') momtot(1:ndmag)
      call flushifc(63)
    end if
! output effective fields for fixed spin moment calculations
    if (fixspin.ne.0) call writefsm(60)
! check for WRITE file
    inquire(file='WRITE',exist=exist)
    if (exist) then
      write(60,*)
      write(60,'("WRITE file exists - writing STATE.OUT")')
      call writestate
      open(50,file='WRITE')
      close(50,status='DELETE')
    end if
! write STATE.OUT file if required
    if (nwrite.ge.1) then
      if (mod(iscl,nwrite).eq.0) then
        call writestate
        write(60,*)
        write(60,'("Wrote STATE.OUT")')
      end if
    end if
  end if
! exit self-consistent loop if required
  if (tlast) goto 20
! check for convergence
  if (iscl.ge.2) then
    if (mp_mpi) then
      write(60,*)
      write(60,'("RMS change in effective potential (target) : ",G18.10," (",&
       &G18.10,")")') dv,epspot
      write(65,'(G18.10)') dv
      call flushifc(65)
    end if
    de=abs(engytot-etp)
    if (mp_mpi) then
      write(60,'("Absolute change in total energy (target)   : ",G18.10," (",&
       &G18.10,")")') de,epsengy
      write(66,'(G18.10)') de
      call flushifc(66)
    end if
    if ((dv.lt.epspot).and.(de.lt.epsengy)) then
      if (mp_mpi) then
        write(60,*)
        write(60,'("Convergence targets achieved")')
      end if
      tlast=.true.
    end if
  end if
  etp=engytot
  if ((xctype(1).lt.0).and.mp_mpi) then
    write(60,*)
    write(60,'("Magnitude of OEP residual : ",G18.10)') resoep
  end if
! check for STOP file (only master process)
  if (mp_mpi) then
    inquire(file='STOP',exist=exist)
    if (exist) then
      write(60,*)
      write(60,'("STOP file exists - stopping self-consistent loop")')
      open(50,file='STOP')
      close(50,status='DELETE')
      tlast=.true.
    end if
  end if
! broadcast tlast from master process to all other processes
  call mpi_bcast(tlast,1,mpi_logical,0,mpi_comm_world,ierror)
! output the current total CPU time
  timetot=timeinit+timemat+timefv+timesv+timerho+timepot+timefor
  if (mp_mpi) then
    write(60,*)
    write(60,'("Time (CPU seconds) : ",F12.2)') timetot
  end if
! end the self-consistent loop
end do
20 continue
if (mp_mpi) then
  write(60,*)
  write(60,'("+------------------------------+")')
  write(60,'("| Self-consistent loop stopped |")')
  write(60,'("+------------------------------+")')
! write density and potentials to file only if maxscl > 1
  if (maxscl.gt.1) then
    call writestate
    write(60,*)
    write(60,'("Wrote STATE.OUT")')
  end if
end if
!-----------------------!
!     compute forces    !
!-----------------------!
if (tforce) then
  call force
  if (mp_mpi) then
! output forces to INFO.OUT
    call writeforce(60)
! write maximum force magnitude to FORCEMAX.OUT
    write(64,'(G18.10)') forcemax
    call flushifc(64)
  end if
end if
!---------------------------------------!
!     perform structural relaxation     !
!---------------------------------------!
if ((task.eq.2).or.(task.eq.3)) then
  if (mp_mpi) then
    write(60,*)
    write(60,'("Maximum force magnitude (target) : ",G18.10," (",G18.10,")")') &
     forcemax,epsforce
    call flushifc(60)
  end if
! check force convergence
  if (forcemax.le.epsforce) then
    if (mp_mpi) then
      write(60,*)
      write(60,'("Force convergence target achieved")')
    end if
    goto 30
  end if
! update the atomic positions if forces are not converged
  call updatpos
  if (mp_mpi) then
! write optimised atomic positions and interatomic distances to file
    call writegeom(.true.)
    call writeiad(.true.)
    write(60,*)
    write(60,'("+--------------------------+")')
    write(60,'("| Updated atomic positions |")')
    write(60,'("+--------------------------+")')
    do is=1,nspecies
      write(60,*)
      write(60,'("Species : ",I4," (",A,")")') is,trim(spsymb(is))
      write(60,'(" atomic positions (lattice) :")')
      do ia=1,natoms(is)
        write(60,'(I4," : ",3F14.8)') ia,atposl(:,ia,is)
      end do
    end do
! add blank line to TOTENERGY.OUT, FERMIDOS.OUT, MOMENT.OUT and RMSDVEFF.OUT
    write(61,*)
    write(62,*)
    if (spinpol) write (63,*)
    write(65,*)
  end if
! begin new self-consistent loop with updated positions
  goto 10
end if
30 continue
! total time used
timetot=timeinit+timemat+timefv+timesv+timerho+timepot+timefor
! output timing information
if (mp_mpi) then
  write(60,*)
  write(60,'("Timings (CPU seconds) :")')
  write(60,'(" initialisation",T40,": ",F12.2)') timeinit
  write(60,'(" Hamiltonian and overlap matrix set up",T40,": ",F12.2)') timemat
  write(60,'(" first-variational secular equation",T40,": ",F12.2)') timefv
  if (spinpol) then
    write(60,'(" second-variational calculation",T40,": ",F12.2)') timesv
  end if
  write(60,'(" charge density calculation",T40,": ",F12.2)') timerho
  write(60,'(" potential calculation",T40,": ",F12.2)') timepot
  if (tforce) then
    write(60,'(" force calculation",T40,": ",F12.2)') timefor
  end if
  write(60,'(" total",T40,": ",F12.2)') timetot
  write(60,*)
  write(60,'("+----------------------------+")')
  write(60,'("| Elk version ",I1.1,".",I1.1,".",I2.2," stopped |")') version
  write(60,'("+----------------------------+")')
! close the INFO.OUT file
  close(60)
! close the TOTENERGY.OUT file
  close(61)
! close the FERMIDOS.OUT file
  close(62)
! close the MOMENT.OUT file
  if (spinpol) close(63)
! close the FORCEMAX.OUT file
  if (tforce) close(64)
! close the RMSDVEFF.OUT file
  close(65)
! close the DTOTENERGY.OUT file
  close(66)
! close TENSMOM.OUT file
  if (tmomlu) close(67)
end if
deallocate(v,work)
return
end subroutine
!EOC
