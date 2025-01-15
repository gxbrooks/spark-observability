What is the different purpose or intention of the Linux directories for /usr/share and for /opt?

	o /usr/share:  
		Purpose: This directory contains architecture-independent data files for software installed on the system. Examples include documentation, icons, localization files, and shared data.

		Intention: The idea is to store data that can be shared across different systems or architectures. For instance, translation files, man pages, and graphics, which do not depend on the hardware or operating system's specifics.

	o /opt
		Purpose: This directory is used for installing optional or third-party software packages. It's often used for software that is not part of the official distribution but provided by vendors or third-party developers.

		Intention: The goal is to provide a standardized place for software packages that do not conform to the usual file hierarchy of the system. It allows for easier management and isolation of these packages, making it simpler to install, upgrade, or remove them.

In summary:

/usr/share is for system-wide, architecture-independent data.

/opt is for optional or third-party software installations.