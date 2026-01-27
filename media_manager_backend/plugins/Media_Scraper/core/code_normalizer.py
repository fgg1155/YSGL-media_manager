"""
番号规范化器
负责在 DVD ID 和 CID 之间转换，参考 JavSP 的 avid.py 实现
"""

import re
from dataclasses import dataclass
from typing import Optional


@dataclass
class CodeInfo:
    """番号信息"""
    dvdid: Optional[str]  # DVD ID 格式（如 IPX-177）
    cid: Optional[str]    # CID 格式（如 ipx00177）
    code_type: str        # 番号类型


class CodeNormalizer:
    """番号规范化器 - 参考 JavSP 的 avid.py"""
    
    # 老番号厂商前缀映射表（DVD ID 前缀 -> CID 数字前缀）
    OLD_FORMAT_PREFIXES = {
        'SMA': '83',
        'MDLD': 'mdld',
        'ONED': 'oned',
        # 可以根据需要添加更多映射
    }
    
    # 欧美厂商缩写映射表（缩写 -> 完整名称）- 来自 MDCX
    WESTERN_STUDIO_MAP = {
        "wgp": "WhenGirlsPlay",
        "18og": "18OnlyGirls",
        "18yo": "18YearsOld",
        "1kf": "1000Facials",
        "21ea": "21EroticAnal",
        "21fa": "21FootArt",
        "21n": "21Naturals",
        "2cst": "2ChicksSameTime",
        "a1o1": "Asian1on1",
        "aa": "AmateurAllure",
        "ad": "AmericanDaydreams",
        "agm": "AllGirlMassage",
        "am": "AssMasterpiece",
        "analb": "AnalBeauty",
        "baebz": "Baeb",
        "bblib": "BigButtsLikeItBig",
        "bcasting": "BangCasting",
        "bconfessions": "BangConfessions",
        "bglamkore": "BangGlamkore",
        "bgonzo": "BangGonzo",
        "brealteens": "BangRealTeens",
        "bcb": "BigCockBully",
        "bch": "BigCockHero",
        "bdpov": "BadDaddyPOV",
        "bex": "BrazzersExxtra",
        "bgb": "BabyGotBoobs",
        "bgbs": "BoundGangbangs",
        "bin": "BigNaturals",
        "bjf": "BlowjobFridays",
        "bp": "ButtPlays",
        "btas": "BigTitsatSchool",
        "btaw": "BigTitsatWork",
        "btc": "BigTitCreampie",
        "btis": "BigTitsinSports",
        "btiu": "BigTitsinUniform",
        "btlbd": "BigTitsLikeBigDicks",
        "btra": "BigTitsRoundAsses",
        "burna": "BurningAngel",
        "bwb": "BigWetButts",
        "cfnm": "ClothedFemaleNudeMale",
        "clip": "LegalPorno",
        "cps": "CherryPimps",
        "cuf": "CumFiesta",
        "cws": "CzechWifeSwap",
        "da": "DoctorAdventures",
        "dbm": "DontBreakMe",
        "dc": "DorcelVision",
        "ddfb": "DDFBusty",
        "ddfvr": "DDFNetworkVR",
        "dm": "DirtyMasseur",
        "dnj": "DaneJones",
        "dpg": "DigitalPlayground",
        "dwc": "DirtyWivesClub",
        "dwp": "DayWithAPornstar",
        "dsw": "DaughterSwap",
        "esp": "EuroSexParties",
        "ete": "EuroTeenErotica",
        "ext": "ExxxtraSmall",
        "fams": "FamilyStrokes",
        "faq": "FirstAnalQuest",
        "fds": "FakeDrivingSchool",
        "fft": "FemaleFakeTaxi",
        "fhd": "FantasyHD",
        "fhl": "FakeHostel",
        "fho": "FakehubOriginals",
        "fka": "FakeAgent",
        "fm": "FuckingMachines",
        "fms": "FantasyMassage",
        "frs": "FitnessRooms",
        "ft": "FastTimes",
        "ftx": "FakeTaxi",
        "gft": "GrandpasFuckTeens",
        "gbcp": "GangbangCreampie",
        "gta": "GirlsTryAnal",
        "gw": "GirlsWay",
        "h1o1": "Housewife1on1",
        "ham": "HotAndMean",
        "hart": "Hegre",
        "hcm": "HotCrazyMess",
        "hegre-art": "Hegre",
        "hoh": "HandsOnHardcore",
        "hotab": "HouseofTaboo",
        "ht": "Hogtied",
        "ihaw": "IHaveAWife",
        "iktg": "IKnowThatGirl",
        "il": "ImmoralLive",
        "kha": "KarupsHA",
        "kow": "KarupsOW",
        "kpc": "KarupsPC",
        "la": "LatinAdultery",
        "lcd": "LittleCaprice-Dreams",
        "littlecaprice": "LittleCaprice-Dreams",
        "lhf": "LoveHerFeet",
        "lsb": "Lesbea",
        "lst": "LatinaSexTapes",
        "lta": "LetsTryAnal",
        "maj": "ManoJob",
        "mbb": "MommyBlowsBest",
        "mbt": "MomsBangTeens",
        "mc": "MassageCreep",
        "mcu": "MonsterCurves",
        "mdhf": "MyDaughtersHotFriend",
        "mdhg": "MyDadsHotGirlfriend",
        "mfa": "ManuelFerrara",
        "mfhg": "MyFriendsHotGirl",
        "mfhm": "MyFriendsHotMom",
        "mfl": "Mofos",
        "mfp": "MyFamilyPies",
        "mfst": "MyFirstSexTeacher",
        "mgbf": "MyGirlfriendsBustyFriend",
        "mgb": "MommyGotBoobs",
        "mic": "MomsInControl",
        "mj": "ManoJob",
        "mlib": "MildsLikeItBig",
        "mlt": "MomsLickTeens",
        "mmgs": "MommysGirl",
        "mnm": "MyNaughtyMassage",
        "mom": "MomXXX",
        "mpov": "MrPOV",
        "mrs": "MassageRooms",
        "mshf": "MySistersHotFriend",
        "mts": "MomsTeachSex",
        "mvft": "MyVeryFirstTime",
        "mwhf": "MyWifesHotFriend",
        "naf": "NeighborAffair",
        "nam": "NaughtyAmerica",
        "na": "NaughtyAthletics",
        "naughtyamericavr": "NaughtyAmerica",
        "nb": "NaughtyBookworms",
        "news": "NewSensations",
        "nf": "NubileFilms",
        "no": "NaughtyOffice",
        "nrg": "NaughtyRichGirls",
        "nubilef": "NubileFilms",
        "num": "NuruMassage",
        "nw": "NaughtyWeddings",
        "obj": "OnlyBlowjob",
        "otb": "OnlyTeenBlowjobs",
        "pav": "PixAndVideo",
        "pba": "PublicAgent",
        "pf": "PornFidelity",
        "phd": "PassionHD",
        "plib": "PornstarsLikeitBig",
        "pop": "PervsOnPatrol",
        "ppu": "PublicPickups",
        "prdi": "PrettyDirty",
        "ps": "PropertySex",
        "pud": "PublicDisgrace",
        "reg": "RealExGirlfriends",
        "rkp": "RKPrime",
        "rws": "RealWifeStories",
        "saf": "ShesAFreak",
        "sart": "SexArt",
        "sbj": "StreetBlowjobs",
        "sislove": "SisLovesMe",
        "smb": "ShareMyBF",
        "ssc": "StepSiblingsCaught",
        "ssn": "ShesNew",
        "sts": "StrandedTeens",
        "swsn": "SwallowSalon",
        "tdp": "TeensDoPorn",
        "tds": "TheDickSuckers",
        "ted": "Throated",
        "tf": "TeenFidelity",
        "tgs": "ThisGirlSucks",
        "these": "TheStripperExperience",
        "tla": "TeensLoveAnal",
        "tlc": "TeensLoveCream",
        "tle": "TheLifeErotic",
        "tlhc": "TeensLoveHugeCocks",
        "tlib": "TeensLikeItBig",
        "tlm": "TeensLoveMoney",
        "togc": "TonightsGirlfriendClassic",
        "tog": "TonightsGirlfriend",
        "tspa": "TrickySpa",
        "tss": "ThatSitcomShow",
        "tuf": "TheUpperFloor",
        "wa": "WhippedAss",
        "wfbg": "WeFuckBlackGirls",
        "wkp": "Wicked",
        "wlt": "WeLiveTogether",
        "woc": "WildOnCam",
        "wov": "WivesOnVacation",
        "wowg": "WowGirls",
        "wy": "WebYoung",
        "zzs": "ZZseries",
        "ztod": "ZeroTolerance",
        "itc": "InTheCrack",
        "abbw": "AbbyWinters",
        "abme": "AbuseMe",
        "ana": "AnalAngels",
        "atke": "ATKExotics",
        # Vixen 系列
        "blacked": "Blacked",
        "tushy": "Tushy",
        "vixen": "Vixen",
        "deeper": "Deeper",
        "slayed": "Slayed",
    }
    
    
    @staticmethod
    def normalize(code: str) -> CodeInfo:
        """
        规范化番号，返回 DVD ID 和 CID
        
        Args:
            code: 输入的番号或文件名
        
        Returns:
            CodeInfo: 包含 dvdid, cid 和 code_type
        
        Examples:
            "IPX-177" -> CodeInfo(dvdid="IPX-177", cid="ipx00177", type="normal")
            "ipx00177" -> CodeInfo(dvdid="IPX-177", cid="ipx00177", type="normal")
            "FC2-PPV-1234567" -> CodeInfo(dvdid="FC2-PPV-1234567", cid="fc2ppv1234567", type="fc2")
        """
        if not code:
            return CodeInfo(dvdid=None, cid=None, code_type='unknown')
        
        # 清理输入：移除文件扩展名、路径、域名等
        code = CodeNormalizer._clean_input(code)
        
        # 识别番号类型并规范化（传入原始大小写）
        code_type = CodeNormalizer._identify_type(code.upper())
        
        if code_type == 'fc2':
            return CodeNormalizer._normalize_fc2(code.upper())
        elif code_type == 'heyzo':
            return CodeNormalizer._normalize_heyzo(code.upper())
        elif code_type == 'heydouga':
            return CodeNormalizer._normalize_heydouga(code.upper())
        elif code_type == 'tokyo_hot':
            return CodeNormalizer._normalize_tokyo_hot(code.upper())
        elif code_type == 'getchu':
            return CodeNormalizer._normalize_getchu(code.upper())
        elif code_type == 'gyutto':
            return CodeNormalizer._normalize_gyutto(code.upper())
        elif code_type == '259luxu':
            return CodeNormalizer._normalize_259luxu(code.upper())
        elif code_type == 'mugen':
            return CodeNormalizer._normalize_mugen(code.upper())
        elif code_type == 'ibw_z':
            return CodeNormalizer._normalize_ibw_z(code.upper())
        elif code_type == 'tma':
            return CodeNormalizer._normalize_tma(code.upper())
        elif code_type == 'r18':
            return CodeNormalizer._normalize_r18(code.upper())
        elif code_type == 'ippondo_10musume':
            return CodeNormalizer._normalize_ippondo_10musume(code)
        elif code_type == 'ippondo_network':
            return CodeNormalizer._normalize_ippondo_network(code)
        elif code_type == 'pure_number':
            return CodeNormalizer._normalize_pure_number(code)
        elif code_type == 'mywife':
            return CodeNormalizer._normalize_mywife(code)
        elif code_type == 'mmr':
            return CodeNormalizer._normalize_mmr(code.upper())
        elif code_type == 'madou':
            return CodeNormalizer._normalize_madou(code.upper())
        elif code_type == 'xxx_av':
            return CodeNormalizer._normalize_xxx_av(code.upper())
        elif code_type == 'mky':
            return CodeNormalizer._normalize_mky(code.upper())
        elif code_type == 'pacopacomama':
            return CodeNormalizer._normalize_pacopacomama(code.upper())
        elif code_type == 'kin8':
            return CodeNormalizer._normalize_kin8(code.upper())
        elif code_type == 'th101':
            return CodeNormalizer._normalize_th101(code.lower())
        elif code_type == 'amateur':
            return CodeNormalizer._normalize_amateur(code.upper())
        elif code_type == 'h_prefix':
            return CodeNormalizer._normalize_h_prefix(code.upper())
        elif code_type == 'domestic':
            return CodeNormalizer._normalize_domestic(code.upper())
        elif code_type == 'cid_only':
            return CodeNormalizer._normalize_cid_only(code)
        else:  # normal
            return CodeNormalizer._normalize_normal(code)
    
    @staticmethod
    def _identify_type(norm: str) -> str:
        """识别番号类型"""
        # FC2 系列
        if 'FC2' in norm:
            return 'fc2'
        
        # HEYDOUGA 系列
        if 'HEYDOUGA' in norm or (norm.startswith('HEY') and re.search(r'HEY[-_]*\d{4}[-_]0?\d{3,5}', norm)):
            return 'heydouga'
        
        # HEYZO 系列
        if 'HEYZO' in norm:
            return 'heyzo'
        
        # GETCHU
        if norm.startswith('GETCHU'):
            return 'getchu'
        
        # GYUTTO
        if norm.startswith('GYUTTO'):
            return 'gyutto'
        
        # 259LUXU 特殊格式
        if '259LUXU' in norm:
            return '259luxu'
        
        # MUGEN 厂商番号
        if re.match(r'(MKB?D?)[-_]*(S\d{2,3})|(MK3D2DBD|S2M|S2MBD|CW3D2DBD|CW3D2D|MCB3DBD|MCB3D)[-_]*(\d{2,3})', norm):
            return 'mugen'
        
        # IBW 后缀 z 的番号
        if re.match(r'IBW[-_]\d{2,5}Z', norm):
            return 'ibw_z'
        
        # 东热系列（RED, SKY, EX, N, K）
        if re.match(r'^RED0[01]\d\d$', norm):  # RED0100-RED0199
            return 'tokyo_hot'
        if re.match(r'^SKY0[0-3]\d\d$', norm):  # SKY000-SKY0399
            return 'tokyo_hot'
        if re.match(r'^EX00[01]\d$', norm):  # EX0000-EX0019
            return 'tokyo_hot'
        if re.match(r'^[NK]\d{4}$', norm):
            return 'tokyo_hot'
        
        # TMA 制作番号
        if re.match(r'^T(28|38)[-_]\d{3}$', norm):
            return 'tma'
        
        # R18-XXX 格式
        if re.match(r'^R18[-_]?\d{3}$', norm):
            return 'r18'
        
        # 一本道系列番号（需要在 pure_number 之前判断，因为格式更具体）
        # 10musume 番号：格式 010120_01 或 010120-01 (6位日期 + 2位编号)
        if re.match(r'^\d{6}[-_]\d{2}$', norm):
            return 'ippondo_10musume'
        
        # 一本道/Pacopacomama/Caribbeancom/CaribbeancomPR 番号：格式 012426_100 或 082713-417 (6位日期 + 3位编号)
        if re.match(r'^\d{6}[-_]\d{3}$', norm):
            return 'ippondo_network'
        
        # 纯数字番号（其他无码，如果上面都不匹配）
        if re.match(r'^\d{6}[-_]\d{2,3}$', norm):
            return 'pure_number'
        
        # MYWIFE 系列
        if 'MYWIFE' in norm or re.match(r'^MYWIFE\s*NO\.?\d+', norm):
            return 'mywife'
        
        # MMR 系列
        if re.match(r'^MMR[-_]?[A-Z]{2}\d+[A-Z]{0,2}$', norm):
            return 'mmr'
        
        # 麻豆传媒系列
        if re.match(r'^MD[A-Z]?[-_]\d{4}[-_]?\d*$', norm):
            return 'madou'
        
        # XXX-AV 系列
        if re.match(r'^XXX[-_]AV[-_]\d+$', norm):
            return 'xxx_av'
        
        # MKY 系列
        if re.match(r'^MKY[-_][A-Z]+[-_]\d+$', norm):
            return 'mky'
        
        # H4610/C0930/H0930 系列
        if re.match(r'^(H4610|C0930|H0930)[-_]KI\d{6}$', norm):
            return 'pacopacomama'
        
        # KIN8TENGOKU 系列
        if 'KIN8' in norm or 'KIN8TENGOKU' in norm:
            return 'kin8'
        
        # TH101 系列
        if re.match(r'^TH101[-_]\d{3}[-_]\d{6}$', norm):
            return 'th101'
        
        # 素人系列（SIRO, LUXU 等）
        if re.match(r'^(SIRO|LUXU|GANA|MAAN|SIMM|KTKC|KTKZ|KTKP|KTKQ|KTKY)[-_]?\d{3,4}$', norm):
            return 'amateur'
        
        # H_ 开头的番号
        if re.match(r'^H_\d+[A-Z]+\d+$', norm):
            return 'h_prefix'
        
        # 国产番号（91CM, PMS, MDUS, REAL野性派）
        if re.match(r'^(91CM|PMS|MDUS|REAL野性派)[-_]?\d+', norm):
            return 'domestic'
        
        # 检查是否为纯 CID 格式（小写字母+数字+下划线）
        if CodeNormalizer._is_cid_format(norm.lower()):
            return 'cid_only'
        
        # 默认为普通番号
        return 'normal'
    
    @staticmethod
    def _is_cid_format(code: str) -> bool:
        """判断是否为 CID 格式"""
        # CID 只由小写字母、数字和下划线组成
        if not re.match(r'^[a-z\d_]+$', code):
            return False
        
        # 检查是否为老番号格式（数字开头+字母+数字，如 83sma132）
        # 这种格式应该被识别为普通番号，而不是纯 CID
        if re.match(r'^\d{2}[a-z]{2,10}\d{2,5}$', code):
            return False  # 这是老番号格式，应该能转换为 DVD ID
        
        # 包含下划线的 CID（常见格式）
        if '_' in code:
            patterns = [
                r'^h_\d{3,4}[a-z]{1,10}\d{2,5}[a-z\d]{0,8}$',  # h_1234abcd56789
                r'^\d{3}_\d{4,5}$',                             # 123_4567
                r'^402[a-z]{3,6}\d*_[a-z]{3,8}\d{5,6}$',        # 402abc_def12345
                r'^h_\d{3,4}wvr\d\w\d{4,5}[a-z\d]{0,8}$',      # h_1234wvr1a12345
            ]
            
            for pattern in patterns:
                if re.match(pattern, code):
                    return True
        
        # 不包含下划线的 CID
        # 长度为 7-19 的纯小写字母+数字
        # 但要排除可能是普通番号的情况（如 ipx00177 应该被识别为普通番号）
        if re.match(r'^[a-z\d]{7,19}$', code):
            # 如果匹配普通番号模式（字母+数字），则不是纯 CID
            if re.match(r'^[a-z]{2,10}\d{2,5}$', code):
                return False  # 这是普通番号的 CID 格式，应该能转换回 DVD ID
            return True
        
        return False
    
    @staticmethod
    def _normalize_normal(code: str) -> CodeInfo:
        """规范化普通番号"""
        norm = code.upper()
        
        # 如果已经是 DVD ID 格式（包含连字符）
        if '-' in norm:
            match = re.search(r'([A-Z]{2,10})[-_](\d{2,5})', norm)
            if match:
                prefix, number = match.groups()
                dvdid = f"{prefix}-{number}"
                
                # 检查是否是老番号（需要特殊前缀）
                if prefix in CodeNormalizer.OLD_FORMAT_PREFIXES:
                    # 老番号：SMA-132 -> 83sma132（不补零）
                    old_prefix = CodeNormalizer.OLD_FORMAT_PREFIXES[prefix]
                    cid = f"{old_prefix}{prefix.lower()}{number}"
                else:
                    # 普通番号：IPX-177 -> ipx00177（补零）
                    cid = f"{prefix.lower()}{number.zfill(5)}"
                
                return CodeInfo(dvdid=dvdid, cid=cid, code_type='normal')
        
        # 处理老番号格式：数字开头+字母+数字（如 83sma132）
        # 这种格式通常是 CID，需要转换为 DVD ID
        # 注意：老番号查询 Fanza 时不能补零，必须保持原样
        old_format_match = re.match(r'^(\d{2})([a-z]{2,10})(\d{2,5})$', code.lower())
        if old_format_match:
            prefix_num, prefix_alpha, number = old_format_match.groups()
            # 83sma132 -> SMA-132, CID: 83sma132（保持原样，不补零）
            prefix = prefix_alpha.upper()
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix_num}{prefix_alpha}{number}"  # 保持原样，不补零
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='normal')
        
        # 如果是无连字符格式，尝试分离前缀和数字
        match = re.search(r'([A-Z]{2,10})(\d{2,5})', norm)
        if match:
            prefix, number = match.groups()
            
            # 处理补零格式：SSNI00644 -> SSNI-644
            # 如果数字部分是5位且以00开头，去除前导00
            if len(number) == 5 and number.startswith('00'):
                # 补零格式：00644 -> 644
                number_stripped = number.lstrip('0') or '0'
                dvdid = f"{prefix}-{number_stripped}"
                cid = f"{prefix.lower()}{number}"  # CID 保持5位
            elif len(number) == 5:
                # 5位数字但不是00开头：00177 -> 177
                number_int = str(int(number))
                dvdid = f"{prefix}-{number_int}"
                cid = f"{prefix.lower()}{number}"
            else:
                # 2-4位数字，保持原样
                dvdid = f"{prefix}-{number}"
                cid = f"{prefix.lower()}{number.zfill(5)}"
            
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='normal')
        
        # 无法识别
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='unknown')
    
    @staticmethod
    def _normalize_fc2(norm: str) -> CodeInfo:
        """规范化 FC2 番号"""
        # 提取数字部分：FC2-PPV-1234567 或 FC2-1234567
        match = re.search(r'FC2[^A-Z\d]{0,5}(PPV[^A-Z\d]{0,5})?(\d{5,7})', norm, re.I)
        if match:
            number = match.group(2)
            dvdid = f"FC2-PPV-{number}"
            cid = f"fc2ppv{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='fc2')
        
        # 无法识别，返回原始值
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='fc2')
    
    @staticmethod
    def _normalize_heyzo(norm: str) -> CodeInfo:
        """规范化 HEYZO 番号"""
        match = re.search(r'HEYZO[-_]*(\d{4})', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"HEYZO-{number}"
            cid = f"heyzo{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='heyzo')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='heyzo')
    
    @staticmethod
    def _normalize_heydouga(norm: str) -> CodeInfo:
        """规范化 HEYDOUGA 番号"""
        # HEYDOUGA-4030-1234 或 HEY-4030-1234
        match = re.search(r'(HEYDOUGA|HEY)[-_]*(\d{4})[-_]0?(\d{3,5})', norm, re.I)
        if match:
            part1, part2 = match.group(2), match.group(3)
            dvdid = f"HEYDOUGA-{part1}-{part2}"
            cid = f"heydouga{part1}{part2}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='heydouga')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='heydouga')
    
    @staticmethod
    def _normalize_tokyo_hot(norm: str) -> CodeInfo:
        """规范化东热番号"""
        # 东热的番号通常不需要特殊转换
        # RED-123, SKY-234, EX-0012, N1234, K1234
        dvdid = norm.upper()
        cid = norm.lower()
        return CodeInfo(dvdid=dvdid, cid=cid, code_type='tokyo_hot')
    
    @staticmethod
    def _normalize_getchu(norm: str) -> CodeInfo:
        """规范化 GETCHU 番号"""
        match = re.search(r'GETCHU[-_]*(\d+)', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"GETCHU-{number}"
            cid = f"getchu{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='getchu')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='getchu')
    
    @staticmethod
    def _normalize_gyutto(norm: str) -> CodeInfo:
        """规范化 GYUTTO 番号"""
        match = re.search(r'GYUTTO[-_]*(\d+)', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"GYUTTO-{number}"
            cid = f"gyutto{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='gyutto')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='gyutto')
    
    @staticmethod
    def _clean_input(code: str) -> str:
        """
        清理输入：移除文件扩展名、路径、域名、标记等
        
        Args:
            code: 原始输入
        
        Returns:
            清理后的番号
        """
        # 移除文件扩展名
        code = re.sub(r'\.(mp4|mkv|avi|wmv|flv|mov|rmvb|rm|mpeg|mpg|ts|m2ts|iso)$', '', code, flags=re.I)
        
        # 移除路径（只保留文件名）
        if '/' in code or '\\' in code:
            code = code.split('/')[-1].split('\\')[-1]
        
        # 移除域名（如 @蜂鳥@FENGNIAO131.VIP-ABP-984）
        code = re.sub(r'@[^@]+@', '', code)
        code = re.sub(r'\w{3,10}\.(COM|NET|APP|XYZ|VIP|CC|TV|ME|IO)', '', code, flags=re.I)
        
        # 移除分段标记（如 _A, _B, -CD1, -CD2, _1, _2）
        # 注意：不要移除麻豆传媒的后缀（如 MD-0165-1）
        # 只移除单字母或 CD/DISC 开头的标记
        code = re.sub(r'[-_](A|B|C|D|CD\d|DISC\d)$', '', code, flags=re.I)
        
        # 移除画质标记（如 -FHD, -4K, -2K, _1080P, _720P）
        code = re.sub(r'[-_](FHD|UHD|4K|2K|1080P|720P|480P)$', '', code, flags=re.I)
        
        # 移除字幕标记（如 -C, C, -UC, _CH, _CHN）
        code = re.sub(r'[-_]?(C|UC|CH|CHN|SUB)$', '', code, flags=re.I)
        
        # 替换特殊分隔符 ')(' 为 '-'
        code = code.replace(')(', '-')
        
        return code.strip()
    
    @staticmethod
    def _normalize_259luxu(norm: str) -> CodeInfo:
        """规范化 259LUXU 系列番号"""
        match = re.search(r'259LUXU[-_]?(\d{4})', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"259LUXU-{number}"
            cid = f"259luxu{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='259luxu')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='259luxu')
    
    @staticmethod
    def _normalize_mugen(norm: str) -> CodeInfo:
        """规范化 MUGEN 厂商番号"""
        # MKB-S123, MKBD-S143, MK3D2DBD-01, S2M-007, S2MBD-007, CW3D2DBD-11, MCB3DBD-33
        match = re.search(r'(MKB?D?)[-_]*(S\d{2,3})|(MK3D2DBD|S2M|S2MBD|CW3D2DBD|CW3D2D|MCB3DBD|MCB3D)[-_]*(\d{2,3})', norm, re.I)
        if match:
            if match.group(1):
                prefix = match.group(1)
                number = match.group(2)
            else:
                prefix = match.group(3)
                number = match.group(4)
            
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number.lower()}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='mugen')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='mugen')
    
    @staticmethod
    def _normalize_ibw_z(norm: str) -> CodeInfo:
        """规范化 IBW 后缀 z 的番号"""
        match = re.search(r'(IBW)[-_](\d{2,5}Z)', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number.lower()}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='ibw_z')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='ibw_z')
    
    @staticmethod
    def _normalize_tma(norm: str) -> CodeInfo:
        """规范化 TMA 制作番号"""
        match = re.search(r'(T(?:28|38))[-_](\d{3})', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='tma')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='tma')
    
    @staticmethod
    def _normalize_r18(norm: str) -> CodeInfo:
        """规范化 R18-XXX 格式番号"""
        match = re.search(r'(R18)[-_]?(\d{3})', norm, re.I)
        if match:
            number = match.group(2)
            dvdid = f"R18-{number}"
            cid = f"r18{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='r18')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='r18')
    
    @staticmethod
    def _normalize_pure_number(code: str) -> CodeInfo:
        """规范化纯数字番号（其他无码，不属于一本道系列）"""
        # 062620-001, 122520-001
        match = re.search(r'(\d{6})[-_](\d{2,3})', code)
        if match:
            part1 = match.group(1)
            part2 = match.group(2)
            dvdid = f"{part1}-{part2}"
            cid = f"{part1}{part2}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='pure_number')
        
        return CodeInfo(dvdid=code, cid=code, code_type='pure_number')
    
    @staticmethod
    def _normalize_ippondo_10musume(code: str) -> CodeInfo:
        """规范化 10musume 番号（6位日期 + 2位编号）"""
        # 010120_01 或 010120-01
        match = re.search(r'(\d{6})[-_](\d{2})', code)
        if match:
            part1 = match.group(1)
            part2 = match.group(2)
            # 统一使用下划线格式
            dvdid = f"{part1}_{part2}"
            cid = f"{part1}{part2}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='ippondo_10musume')
        
        return CodeInfo(dvdid=code, cid=code, code_type='ippondo_10musume')
    
    @staticmethod
    def _normalize_ippondo_network(code: str) -> CodeInfo:
        """规范化一本道系列番号（6位日期 + 3位编号）
        
        包括：1Pondo, Pacopacomama, Caribbeancom, CaribbeancomPR
        注意：这些网站使用相同的番号格式，但内容可能不同
        """
        # 012426_100 或 082713-417
        match = re.search(r'(\d{6})[-_](\d{3})', code)
        if match:
            part1 = match.group(1)
            part2 = match.group(2)
            # 统一使用下划线格式
            dvdid = f"{part1}_{part2}"
            cid = f"{part1}{part2}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='ippondo_network')
        
        return CodeInfo(dvdid=code, cid=code, code_type='ippondo_network')
    
    @staticmethod
    def _normalize_mywife(code: str) -> CodeInfo:
        """规范化 MYWIFE 系列番号"""
        # MYWIFE No.1111 或 MYWIFE-1111
        match = re.search(r'MYWIFE\s*(?:NO\.?|[-_])?(\d+)', code, re.I)
        if match:
            number = match.group(1)
            dvdid = f"Mywife No.{number}"
            cid = f"mywife{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='mywife')
        
        return CodeInfo(dvdid=code, cid=code.lower(), code_type='mywife')
    
    @staticmethod
    def _normalize_mmr(norm: str) -> CodeInfo:
        """规范化 MMR 系列番号"""
        # MMR-AK089SP -> MMRAK089SP
        match = re.search(r'MMR[-_]?([A-Z]{2}\d+[A-Z]{0,2})', norm, re.I)
        if match:
            suffix = match.group(1)
            dvdid = f"MMR{suffix}"
            cid = f"mmr{suffix.lower()}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='mmr')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='mmr')
    
    @staticmethod
    def _normalize_madou(norm: str) -> CodeInfo:
        """规范化麻豆传媒番号"""
        # MD-0165-1, MDX-0236-02
        match = re.search(r'(MD[A-Z]?)[-_](\d{4})[-_](\d+)', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            suffix = match.group(3)
            
            dvdid = f"{prefix}-{number}-{suffix}"
            cid = f"{prefix.lower()}{number}{suffix}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='madou')
        
        # 没有后缀的情况
        match = re.search(r'(MD[A-Z]?)[-_](\d{4})', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='madou')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='madou')
    
    @staticmethod
    def _normalize_xxx_av(norm: str) -> CodeInfo:
        """规范化 XXX-AV 系列番号"""
        match = re.search(r'XXX[-_]AV[-_](\d+)', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"XXX-AV-{number}"
            cid = f"xxxav{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='xxx_av')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='xxx_av')
    
    @staticmethod
    def _normalize_mky(norm: str) -> CodeInfo:
        """规范化 MKY 系列番号"""
        # MKY-A-11111, MKY-HS-004
        match = re.search(r'MKY[-_]([A-Z]+)[-_](\d+)', norm, re.I)
        if match:
            letter = match.group(1)
            number = match.group(2)
            dvdid = f"MKY-{letter}-{number}"
            cid = f"mky{letter.lower()}{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='mky')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='mky')
    
    @staticmethod
    def _normalize_pacopacomama(norm: str) -> CodeInfo:
        """规范化 H4610/C0930/H0930 系列番号"""
        # H4610-ki111111, C0930-ki221218
        match = re.search(r'(H4610|C0930|H0930)[-_](KI\d{6})', norm, re.I)
        if match:
            prefix = match.group(1)
            suffix = match.group(2)
            dvdid = f"{prefix}-{suffix}"
            cid = f"{prefix.lower()}{suffix.lower()}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='pacopacomama')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='pacopacomama')
    
    @staticmethod
    def _normalize_kin8(norm: str) -> CodeInfo:
        """规范化 KIN8TENGOKU 系列番号"""
        # KIN8-1234, KIN8TENGOKU-1234 -> KIN8-1234
        match = re.search(r'KIN8(?:TENGOKU)?[-_]?(\d{4})', norm, re.I)
        if match:
            number = match.group(1)
            dvdid = f"KIN8-{number}"
            cid = f"kin8{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='kin8')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='kin8')
    
    @staticmethod
    def _normalize_th101(code: str) -> CodeInfo:
        """规范化 TH101 系列番号（小写）"""
        # TH101-140-112594 -> th101-140-112594
        match = re.search(r'(TH101)[-_](\d{3})[-_](\d{6})', code, re.I)
        if match:
            dvdid = f"th101-{match.group(2)}-{match.group(3)}"
            cid = f"th101{match.group(2)}{match.group(3)}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='th101')
        
        return CodeInfo(dvdid=code.lower(), cid=code.lower(), code_type='th101')
    
    @staticmethod
    def _normalize_amateur(norm: str) -> CodeInfo:
        """规范化素人系列番号"""
        # 259LUXU-1456, SIRO-1175
        match = re.search(r'(SIRO|LUXU|GANA|MAAN|SIMM|KTKC|KTKZ|KTKP|KTKQ|KTKY)[-_]?(\d{3,4})', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='amateur')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='amateur')
    
    @staticmethod
    def _normalize_h_prefix(norm: str) -> CodeInfo:
        """规范化 H_ 开头的番号"""
        # H_173MEGA05 -> MEGA-05
        match = re.search(r'H_\d+([A-Z]+)(\d+)', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix.lower()}{number.zfill(5)}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='h_prefix')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='h_prefix')
    
    @staticmethod
    def _normalize_domestic(norm: str) -> CodeInfo:
        """规范化国产番号"""
        # 91CM-081, PMS-003.EP3, MDUS系列LAX0025, REAL野性派001
        
        # 处理 EP 标记
        ep_match = re.search(r'\.EP(\d+)', norm, re.I)
        ep_suffix = ''
        if ep_match:
            ep_suffix = f".EP{ep_match.group(1)}"
            norm = re.sub(r'\.EP\d+', '', norm, flags=re.I)
        
        # 91CM-081
        match = re.search(r'(91CM|PMS|MDUS)[-_]?(\d+)', norm, re.I)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}{ep_suffix}"
            cid = f"{prefix.lower()}{number}{ep_suffix.lower()}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='domestic')
        
        # REAL野性派001 -> REAL野性派-001
        match = re.search(r'(REAL野性派)(\d+)', norm)
        if match:
            prefix = match.group(1)
            number = match.group(2)
            dvdid = f"{prefix}-{number}"
            cid = f"{prefix}{number}"
            return CodeInfo(dvdid=dvdid, cid=cid, code_type='domestic')
        
        return CodeInfo(dvdid=norm, cid=norm.lower(), code_type='domestic')
    
    @staticmethod
    def _normalize_cid_only(code: str) -> CodeInfo:
        """规范化纯 CID 格式"""
        # 纯 CID 无法可靠地转换为 DVD ID
        cid = code.lower()
        return CodeInfo(dvdid=None, cid=cid, code_type='cid_only')


if __name__ == '__main__':
    # 测试用例
    test_cases = [
        # 基础测试
        'IPX-177',
        'ipx00177',
        'SSIS-001',
        'ssis00001',
        
        # 老番号格式
        '83sma132',
        'SMA-132',
        'oned00001',
        'ONED-001',
        
        # FC2 系列
        'FC2-PPV-1234567',
        'FC2-1234567',
        
        # HEYZO/HEYDOUGA
        'HEYZO-1234',
        'HEYDOUGA-4030-1234',
        'HEY-4030-1234',
        
        # 东热系列
        'RED0123',
        'SKY0234',
        'EX0012',
        'N1234',
        'K1234',
        
        # 特殊格式
        '259LUXU-1234',
        'GETCHU-12345',
        'GYUTTO-67890',
        
        # MUGEN 厂商
        'MKB-S123',
        'MKBD-S143',
        'MK3D2DBD-01',
        'S2M-007',
        'MCB3DBD-33',
        
        # IBW 后缀 z
        'IBW-398z',
        
        # TMA 制作
        'T28-557',
        'T38-123',
        
        # R18-XXX
        'R18-123',
        
        # 纯数字番号
        '062620-001',
        '122520-001',
        
        # MYWIFE
        'MYWIFE No.1111',
        'MYWIFE-1111',
        
        # MMR 系列
        'MMR-AK089SP',
        
        # 麻豆传媒
        'MD-0165-1',
        'MDX-0236-02',
        
        # XXX-AV
        'XXX-AV-12345',
        
        # MKY 系列
        'MKY-A-11111',
        'MKY-HS-004',
        
        # H4610/C0930/H0930
        'H4610-ki111111',
        'C0930-ki221218',
        
        # KIN8TENGOKU
        'KIN8-1234',
        'KIN8TENGOKU-1234',
        
        # TH101
        'TH101-140-112594',
        
        # 素人系列
        'SIRO-1175',
        '259LUXU-1456',
        
        # H_ 开头
        'H_173MEGA05',
        
        # 国产番号
        '91CM-081',
        'PMS-003.EP3',
        'REAL野性派001',
        
        # 补零格式
        'SSNI00644',
        
        # 文件名清理测试
        '@蜂鳥@FENGNIAO131.VIP-ABP-984.mp4',
        'ABP-984-C-FHD.mp4',
        'ABP-984_A.mp4',
        'ABP-984-CD1.mp4',
        
        # CID 格式
        'h_1234abcd56789',
    ]
    

    print("=== 番号规范化测试 ===\n")
    for code in test_cases:
        result = CodeNormalizer.normalize(code)
        dvdid = result.dvdid or 'None'
        cid = result.cid or 'None'
        print(f"输入: {code:30} -> DVD ID: {dvdid:25} CID: {cid:25} 类型: {result.code_type}")
