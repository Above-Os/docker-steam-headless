#!/usr/bin/env bash

echo "**** Installing/upgrading Steam package ****"

pkg=(
tenfoot_images_all.zip.vz.193cb8c4eb4446698ea2c0a9e8c4e6b6a623dac7_5572671
resources_all.zip.vz.3d492fce87e5ccddbb855f26680b0c6798901010_2867227
strings_all.zip.vz.2bee49ebaa1cf153bea903b50ecdaaeb6770168f_2006028
steamui_websrc_movies_all.zip.4d2183b0476852dfb695b8d70192a0ccece8c7d0
miles_ubuntu12.zip.vz.5093ef941e6e5195a60ab3259077694dec994016_295496
sdl3_ubuntu12.zip.vz.efad8d8e33b4eefbefb0f04baad255ea3e064aae_6347963
steam_ubuntu12.zip.vz.9a27820e0e317c8c302f9ceef6f43bc5e0f00108_2618473
steamui_websrc_all.zip.vz.deeae77fea80a3110c15d0e9a63c2a95ab6ab647_24679493
resources_misc_all.zip.vz.e86a975545f3ab21a77373870cb311ef93934b8c_2224876
public_all.zip.vz.b0ad1267ec973fc34840c92ebbf4b35b0c40cc17_23591292
steamui_websrc_sounds_all.zip.vz.a2b25775b33d943e54c45d176558de379111ef5f_3220470
bins_ubuntu12.zip.vz.f83baf36035930788f01ab03017d333af41dad5c_30138834
bins_sdk_ubuntu12.zip.vz.c30c0a3a11027dd16cabaa3512e15615dd0d4dde_19880133
bins_codecs_ubuntu12.zip.vz.16bd95e339abaabf87d7d50ed4822fc0d67b590d_8752315
bins_misc_ubuntu12.zip.vz.72be98aad8e15e7b92bfccfe7c4268b720870b9c_18827909
webkit_ubuntu12.zip.vz.57c0e0d3866ff0cdaa4af1f0fb2a0393a31a7906_79943183
runtime_scout_ubuntu12.zip.2422dc5093c67022c86b17493e49f66124f182d0
runtime_sniper_ubuntu12.zip.328e060d569aa12d70746dab1f74cd54196edf9c
miles_ubuntu12.zip.vz.5093ef941e6e5195a60ab3259077694dec994016_295496
)

if [[ ${PREINSTALL_STEAM_PACKAGE:-} == "true" ]]; then
    echo "Pre-installing Steam package ... "
    for p in ${pkg[@]}; do
        if [[ ! -f /usr/local/src/$p ]]; then
            echo "Downloading [${p}] ... "
            checksum=$(echo $p|awk -F'.' '{print $NF}'|awk -F'_' '{print $1}')
            retry=10
            while [[ retry -gt 0 ]]; do
                wget -O /usr/local/src/$p http://media.steampowered.com/client/$p
                sum=$(sha1sum /usr/local/src/$p|awk '{print $1}')
                if [[ x"$sum" == x"$checksum" ]]; then
                    break
                fi

                ((retry--))
            done

            if [[ ! -f /usr/local/src/$p ]]; then
                echo "Failed to download [${p}] after multiple attempts, exiting."
                exit 1
            fi
        fi
    done

    echo "Pre-install Steam package DONE"
    exit 0
fi

mkdir -p ${USER_HOME}/.steam/debian-installation/package

for p in ${pkg[@]}; do
    if [[ ! -f ${USER_HOME}/.steam/debian-installation/package/$p ]]; then
        if [[ -f /usr/local/src/$p ]]; then
            echo "Copying pre-downloaded package [${p}] ... "
            cp -v /usr/local/src/$p ${USER_HOME}/.steam/debian-installation/package/$p
        else
            echo "Downloading [${p}] ... "
            checksum=$(echo $p|awk -F'.' '{print $NF}'|awk -F'_' '{print $1}')
            retry=10
            while [[ retry -gt 0 ]]; do
                wget -O ${USER_HOME}/.steam/debian-installation/package/$p http://media.steampowered.com/client/$p
                sum=$(sha1sum ${USER_HOME}/.steam/debian-installation/package/$p|awk '{print $1}')
                if [[ x"$sum" == x"$checksum" ]]; then
                    break
                fi

                ((retry--))
            done
        fi
    fi
done

echo "Install GE-Proton ... "
if [[ ! -f ${USER_HOME}/.steam/debian-installation/compatibilitytools.d/GE-Proton9-15 ]]; then
    mkdir -p ${USER_HOME}/.steam/debian-installation/compatibilitytools.d
    cd ${USER_HOME}/.steam/debian-installation/compatibilitytools.d
    tar zxvf /usr/local/src/GE-Proton9-15.tar.gz
fi

echo "DONE"
