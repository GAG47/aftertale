~~~
$src = "D:\godotproject\aftertale\assets\art\source\head\head_v10"
$dst = "D:\godotproject\aftertale\assets\art\source\head\head_v10_"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem $src -Recurse -File -Filter *.png |
Where-Object {
	$_.FullName -notlike "$dst\*" -and
	$_.Name -notlike "*副本*" -and
	$_.BaseName -notmatch '_(north|east|west)$'
} |
Copy-Item -Destination $dst -Force
~~~

~~~
$src = "D:\godotproject\ai-rpg\asset\hair"
$dst = "D:\godotproject\ai-rpg\asset\hair\front"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem $src -Recurse -File -Filter *.png |
Where-Object {
	$_.FullName -notlike "$dst\*" -and
	$_.Name -notlike "*副本*" -and
	$_.BaseName -notmatch '_(north|east|westm)$'
} |
Copy-Item -Destination $dst -Force
~~~



**批量移动**

~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\set_character_batch_adjustment.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair `
  -OffsetY -40 `
  -Scale 0.65
~~~

~~~
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair `
  -MaxItems 100
~~~



~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\set_character_batch_adjustment.ps1 `
  -BatchId "apparel/apparel_v4_" `
  -Part outfit `
  -OffsetY 15 `
  -Scale 0.5
~~~

~~~
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "apparel/apparel_v4_" `
  -Part outfit `
  -MaxItems 100
~~~



**导入**

~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\standardize_character_batch.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair
~~~



**AI生成素材提示词**（环世界风格小人）

~~~
Use the uploaded body image as the exact template.

Draw clothing on this body and keep the exact body pose, front-facing south-facing direction, body size, and alignment.
Do not redesign the body. Do not create a different character.

Create a modular RPG outfit preview for this character.

Outfit target:
- outfit id: [OUTFIT_ID]
- group: [GROUP]
- outfit type: [OUTFIT_TYPE]
- leg mode: [hidden / partial / visible]
- main color: [MAIN_COLOR]
- secondary color: [SECONDARY_COLOR]
- accent color: [ACCENT_COLOR]
- key details: [KEY_DETAIL_1], [KEY_DETAIL_2]

Style:
- anime-style chibi game asset
- clean dark outline
- soft cel shading
- large readable shapes
- compact silhouette
- readable when scaled down to 64x64
- designed for a modular 2D RPG character

Rules:
- keep the uploaded body proportions
- keep the outfit compact
- if leg mode is hidden, the lower garment should cover the legs
- if leg mode is partial, only a little of the legs or feet may show
- if leg mode is visible, short legs may be visible
- no visible hands
- no weapon
- no held item
- no background scene
- no extra character
- no text
- no watermark
~~~

~~~
Use the uploaded body image as the exact alignment template.

Create ONLY a modular outfit layer for this chibi RPG character.
Do not draw a full character.
Do not draw the body skin, head, face, or hair.

This outfit layer must fit exactly over the uploaded body:
- keep the same front-facing south-facing alignment
- keep the same body proportions
- keep the same clothing position and scale
- leave the head area empty
- leave the neck opening or collar opening properly shaped for the body template

Outfit target:
- outfit id: [OUTFIT_ID]
- group: [GROUP]
- outfit type: [OUTFIT_TYPE]
- leg mode: [hidden / partial / visible]
- main color: [MAIN_COLOR]
- secondary color: [SECONDARY_COLOR]
- accent color: [ACCENT_COLOR]
- key details: [KEY_DETAIL_1], [KEY_DETAIL_2]

Visual style:
- anime-style chibi game asset
- clean dark outline
- soft cel shading
- compact silhouette
- clear readable shapes
- readable when scaled down to 64x64
- modular 2D RPG outfit asset

Rules:
- output clothing only
- no body skin
- no head
- no face
- no hair
- no visible hands
- no weapon
- no held item
- if leg mode is hidden, the outfit should cover the legs
- if leg mode is partial, the lower hem may allow only a small amount of leg or foot visibility
- if leg mode is visible, short legs may remain visible in the final fitted outfit shape
- keep the silhouette compact
- use only one or two strong profession-defining details
- no background scene
- no text
- no watermark
~~~



**AI生成素材提示词**（人物）

~~~
请生成一张日式幻想 SRPG 风格的角色全身立绘。

角色设定：
- 职业：{职业}
- 性别：{性别}
- 年龄感：{年龄感}
- 体型：{体型}
- 气质：{气质}
- 身份关键词：{身份关键词}

外观设定：
- 发型/发色：{发型发色}
- 瞳色：{瞳色}
- 面部特征：{面部特征}
- 种族/特征：{种族特征}

服装与装备：
- 服装风格：{服装风格}
- 主色调：{主色调}
- 材质构成：{材质构成}
- 装饰细节：{装饰细节}
- 武器/道具：{武器道具}

动作与构图：
- 构图：完整全身、单人、白色或纯净浅色背景
- 视角：正面或轻微 3/4 视角
- 姿势：{姿势}
- 表情：{表情}
- 角色轮廓清晰，职业特征一眼可辨

画风要求：
- 日式王道幻想 SRPG / JRPG 角色设定图风格
- 干净细致的动漫线稿
- 柔和赛璐璐上色，带少量淡彩质感
- 低饱和、自然、柔和的配色
- 中世纪轻幻想服装设计
- 布料、皮革、金属材质区分明确
- 画面清爽，适合游戏角色立绘与 UI 展示
- 不要复杂背景，不要强烈特效，不要夸张透视

额外要求：
- 角色设计要有明确职业辨识度
- 服装既有设计感，也要有一定实用性
- 整体气质偏温和、冒险感、王道幻想
- 保持比例自然，人体结构正确，手部清晰

避免：
- 现代服装
- 科幻元素
- 赛博朋克
- 3D 渲染感
- 过度写实
- 厚重油画感
- 高饱和霓虹色
- 杂乱背景
- 动态战斗场面
~~~



ai生成美术

~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名{职业}，{性别}，年龄感约 {年龄感}，体型 {体型}，整体气质 {气质}，身份关键词为 {身份关键词}。角色拥有 {发型发色}、{瞳色}、{面部特征}，并带有 {种族特征}。穿着 {服装风格}，主色调为 {主色调}，材质包含 {材质构成}，配有 {装饰细节}，手持 {武器道具}。

请绘制为完整全身、单人、白色背景，正面或轻微 3/4 视角，姿势 {姿势}，表情 {表情}，角色轮廓清晰，职业特征一眼可辨。

画风统一为：日式幻想 SRPG / JRPG 角色设定图风格，干净清晰的动漫线稿，外轮廓线加粗，线条层级分明，角色剪影清楚，柔和赛璐璐上色，轻微淡彩质感，低饱和自然柔和配色，中世纪轻幻想服装设计，布料、皮革、金属材质区分明确，画面清爽，适合游戏角色立绘与 UI 展示

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常。
~~~

~~~
请根据原角色立绘，生成同一角色的战棋 / SRPG 地图单位小人版本。

角色是一名{职业}，{性别}，整体气质 {气质}，身份关键词为 {身份关键词}。请保留原角色最核心的身份识别特征：{发型发色}、{瞳色}、{面部特征}、{种族特征}；保留核心服装元素：{服装风格}中的主轮廓；保留主色调：{主色调}；保留最关键的职业装备：{武器道具}。但请注意，这里只继承角色身份，不继承原立绘的细节密度、盔甲分片数量、复杂装饰、长腿比例、修长四肢比例和正式立绘展示感；不要把原立绘直接缩成 Q 版，而是要按照统一地图单位模板重新概括为小尺寸战棋单位。

请将角色改写为战棋 / SRPG 地图单位风格的小人：严格固定为 2.7 头身，头部高度约占角色总高度的 38%~40%，完整全身，单人，纯白背景，轻微 3/4 视角，姿势为 {姿势}，表情为 {表情}。角色应优先服务于地图中的小尺寸辨识，请以 64px 显示清晰 为首要目标，而不是大图状态下的精致度。请明显强化“大头小身”的地图单位感，优先保留 头部轮廓、职业武器轮廓、服装主轮廓、主色块对比，其余细节全部尽量收敛。

请显著减少信息密度：发丝不要过多分叉，头发应处理为更概括的大块轮廓；盔甲不要保留过多分片结构，应改为更少、更大的甲块；盾牌、披风、衣摆和裙甲只保留大轮廓，不保留复杂纹章与细碎花纹；腰带、挂包、挂饰、扣件、边饰、金边、小徽章、小挂件尽量删除或合并；内部衣褶、金属拼接、护甲刻线、细小装饰全部减少；武器只保留最关键的大轮廓与基础结构，不保留复杂护手、雕纹和装饰件。请让角色整体更整洁、更概括、更偏大色块与大剪影，确保缩小后依然一眼看出职业与阵营感。

整体应更接近日式幻想 SRPG 的 chibi battle unit / map unit sprite 风格，而不是正式角色立绘，也不是精致 Q 版展示插画。请让单位视觉重心明确，职业识别简单直接。如果“小人感”和“立绘感”发生冲突，请优先选择更偏地图单位小人的表现方式；如果“细节丰富”和“地图可读性”发生冲突，请优先保证地图可读性。全身最终只保留 3~5 个主要识别信息：发型轮廓、主武器轮廓、主服装轮廓、主色块、一个职业符号；其他全部弱化。

画风统一为：日式幻想 SRPG / JRPG 地图单位风格，干净清晰的动漫线稿，外轮廓显著加粗加强，内部线条大幅减少并尽量简洁，角色剪影清楚，柔和赛璐璐上色，阴影简洁明确，大色块关系清楚，低饱和自然柔和配色，中世纪轻幻想服装设计，适合游戏地图与 UI 显示，看起来像战棋游戏中的角色单位，而不是正式角色立绘或普通 Q 版插画。

避免：复杂纹章、复杂盾面图案、复杂盔甲分片、复杂发丝层次、复杂腰带结构、小挂件过多、花纹过多、边饰过多、正式立绘感过强、精致 Q 版展示图感过强、头身比过高、内部细节过多、复杂武器结构、复杂背景、过多特效、人体比例异常、手部崩坏。
~~~

~~~
请将这张图的纯白色背景修改为纯色亮绿色绿幕背景（#00FF00）。只替换背景颜色，角色本体、线稿、颜色、阴影、细节、姿势、表情、武器和服装全部保持不变。背景必须是单一纯色亮绿色。 
~~~



简单版本

~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名{职业}，{性别}，年龄感约 {年龄感}，体型 {体型}，整体气质 {气质}，身份关键词为 {身份关键词}。角色拥有 {发型发色}、{瞳色}、{面部特征}，并带有 {种族特征}。穿着 {服装风格}，主色调为 {主色调}，材质包含 {材质构成}，配有 {装饰细节}，手持 {武器道具}。请注意，装饰细节应有明确主次，只保留能体现职业与身份的核心装饰，不要让发饰、挂件、纹样、腰带、链条、宝石、书本、武器装饰同时抢占视觉重点。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角，姿势为自然站立，{姿势}，武器不要过度遮挡身体，表情 {表情}。角色轮廓清晰，职业特征一眼可辨。整体应像游戏内常规角色立绘，而不是高稀有度卡面、宣传插画或精致展示图。

画风统一为：日式幻想 SRPG / JRPG 角色官方设定图（Official Art）风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚。严格使用柔和赛璐璐平涂（Cel-shading, Flat color），平光照明（Flat lighting），阴影边缘清晰，不使用复杂渐变和厚重光影。整体色彩为低饱和自然柔和配色，轻微淡彩质感，画面清爽干净，适合游戏角色立绘与 UI 展示。

服装设计为中世纪轻幻想风格，布料、皮革、金属材质区分明确，结构合理，层级适中。请优先保证角色的大轮廓、主色块、职业识别和服装结构清晰，不要堆砌过多细碎装饰。花纹、金边、符文、链条、挂饰、宝石、发饰、武器装饰都应适度简化，只作为辅助识别元素，不要覆盖大面积服装或武器。整体应具有可量产的游戏角色设定图质感，而不是 AI 自动堆叠装饰的复杂插画感。

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常、体积光（Volumetric lighting）、边缘光（Rim light）、渐变色叠加、过度的衣褶细节、画面高光泛滥、复杂纹样、复杂链条、过多挂件、过多宝石、过度装饰的武器、信息密度过高、AI 感强的装饰堆砌。
~~~

~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名法师，女性，年龄感约 16~20 岁，体型娇小纤细，整体气质聪慧、神秘、安静，身份关键词为学院魔法师、元素术士、魔导研究者。角色拥有银白色中长发、紫色瞳色、沉静聪慧的面部特征，并带有人类种族特征。穿着宽松法袍与短披肩结合的服装风格，主色调为深蓝色、白色与淡紫色，材质包含柔软布料、魔法织物、少量金属扣件，配有小型魔法书、简洁腰包、少量星形挂饰、少量简洁符文边饰等装饰细节，手持木质法杖与小型魔法书。请注意，装饰细节应有明确主次，法师身份主要通过法杖、法袍、魔法书和紫蓝色调来体现，不要让星形挂饰、符文、腰包、宝石、链条、发饰和法杖装饰同时抢占视觉重点。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角，姿势为自然安静站立，单手持木质法杖，另一只手轻抱小型魔法书或自然垂放在身侧，法杖不要过度遮挡身体，表情为平静专注。角色轮廓清晰，职业特征一眼可辨。整体应像游戏内常规角色立绘，而不是高稀有度卡面、宣传插画或精致展示图。

画风统一为：日式幻想 SRPG / JRPG 角色官方设定图（Official Art）风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚。严格使用柔和赛璐璐平涂（Cel-shading, Flat color），平光照明（Flat lighting），阴影边缘清晰，不使用复杂渐变和厚重光影。整体色彩为低饱和自然柔和配色，轻微淡彩质感，画面清爽干净，适合游戏角色立绘与 UI 展示。

服装设计为中世纪轻幻想风格，布料、皮革、金属材质区分明确，结构合理，层级适中。法袍与短披肩应保留清晰的大轮廓和适量层次，不要堆砌过多细碎装饰。请优先保证角色的大轮廓、主色块、职业识别和服装结构清晰，法杖只保留木质杖身与一个主要水晶或魔法核心，小型魔法书只保留简洁封面和少量符号，披肩与袍摆只保留少量边线与少量符文点缀。花纹、金边、符文、链条、挂饰、宝石、发饰、法杖装饰都应适度简化，只作为辅助识别元素，不要覆盖大面积服装或武器。整体应具有可量产的游戏角色设定图质感，而不是 AI 自动堆叠装饰的复杂插画感。

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常、体积光（Volumetric lighting）、边缘光（Rim light）、渐变色叠加、过度的衣褶细节、画面高光泛滥、复杂法杖结构、大面积复杂符文、复杂链条、过多挂件、过多宝石、复杂披风花纹、信息密度过高、AI 感强的装饰堆砌。
~~~

简单重要npc版本

~~~
生成一张日式幻想 SRPG 风格的重要角色全身立绘。

角色名为伊律德菈·索斯凡纳，女性，外表年龄感约二十五岁，身份为奥瑞利安帝国现任女王，身高 162cm，体型纤细端正，整体气质贤明、聪慧、高贵、威严，带有根植于善良之上的傲慢与自信，身份关键词为女王、贤王、龙使、帝国、守护、繁荣、威严。她拥有垂至膝盖的白色长发，左眼为普通的蓝色眼眸，右眼则如星辰般深蓝，带有白色竖瞳，唇边有两颗尖尖的虎牙。她既有王者的威仪，也带着历经岁月后沉淀出的温柔与坚定。

穿着具有王权象征的中世纪轻幻想女王礼装，主色调为白色、深蓝色、金色，并可融入少量象征龙使身份的深星蓝点缀。材质包含高级布料、丝绸、细腻皮革与精致金属，服装结构可以包含长披风、立领、修身长裙、肩甲或礼仪性腰饰，配有少量帝国纹章、王室装饰与龙使象征细节。手持一把王者佩剑，或一柄兼具礼仪与战斗感的单手长剑。整体设计围绕三个核心视觉记忆点展开：白色长发与异色双眼、女王礼装与帝国王权轮廓、深蓝龙瞳与龙使气息所形成的高贵威严感。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角。姿势为自然站立，身体姿态端庄稳重，可以一手持剑拄地，另一手自然垂放或轻按于身前，展现一位贤王在风雨之后仍立于王座前的姿态。表情平静、自信、威严、聪慧，眼神中带有掌控全局的冷静，也带有对国家与人民的责任感。角色轮廓清晰，剪影鲜明，王者身份、龙使特征与重要角色气场都能一眼辨认，整体具有主控角色级别的存在感与史诗感。

画风统一为：日式幻想 SRPG / JRPG 角色官方设定图风格，干净清晰的动漫线稿，外轮廓线明确加粗，线条层级清晰，角色剪影完整。使用柔和赛璐璐平涂与平光照明，阴影边缘清楚，整体色彩低饱和、自然柔和、轻微淡彩质感，并在白、金、蓝配色中体现王权、繁荣与理性的庄严气息。

服装设计为中世纪轻幻想王权风格，布料、皮革、金属材质区分明确，结构华贵而克制，层级分明。请优先强化角色的大轮廓、主色块、王权身份符号与专属记忆点，使服装结构、色彩分区、佩剑轮廓与装饰重点形成更强的人物个性。整体应体现她作为贤王与龙使的精致度、独特性与角色魅力，同时保持适合游戏角色立绘与 UI 展示的整洁统一感。

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常、体积光（Volumetric lighting）、边缘光（Rim light）、渐变色叠加、过度的衣褶细节、画面高光泛滥、复杂纹样、复杂链条、过多挂件、过多宝石、过度装饰的武器、信息密度过高、AI 感强的装饰堆砌。
~~~

~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名女王，女性，年龄感约二十五岁，体型纤细端正，整体气质贤明、聪慧、威严、高贵，身份关键词为女王、贤王、帝国统治者、龙使、繁荣、守护者。角色拥有垂至膝盖的白色长发、左眼为蓝色眼眸、右眼为如星辰般的深蓝眼眸并带白色竖瞳、面容高贵冷静且带有两颗尖尖虎牙的面部特征，并带有龙使设定的种族特征。穿着王权礼装风格的轻幻想服装，主色调为白色、深蓝色、金色，材质包含高级布料、丝绸、细腻皮革、少量精致金属，配有少量王室纹章、肩部或胸前的帝国象征装饰细节，手持一把兼具王权象征与战斗感的佩剑。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角，姿势为自然站立，身体姿态端庄稳重，双手持剑令剑尖自然朝下，带有王者直面风雨后的沉着气场，武器不要过度遮挡身体，表情冷静、自信、威严，同时隐约体现善良与责任感。角色轮廓清晰，职业特征一眼可辨。整体应像游戏内常规角色立绘，而不是高稀有度卡面、宣传插画或精致展示图。

画风统一为：日式幻想 SRPG / JRPG 角色官方设定图（Official Art）风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚。严格使用柔和赛璐璐平涂（Cel-shading, Flat color），平光照明（Flat lighting），阴影边缘清晰，不使用复杂渐变和厚重光影。整体色彩为低饱和自然柔和配色，轻微淡彩质感，画面清爽干净，适合游戏角色立绘与 UI 展示。

服装设计为中世纪轻幻想风格，布料、皮革、金属材质区分明确，结构合理，层级适中。请优先保证角色的大轮廓、主色块、职业识别和服装结构清晰，不要堆砌过多细碎装饰。花纹、金边、符文、链条、挂饰、宝石、发饰、武器装饰都应适度简化，只作为辅助识别元素，不要覆盖大面积服装或武器。整体应具有可量产的游戏角色设定图质感，而不是 AI 自动堆叠装饰的复杂插画感。

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常、体积光（Volumetric lighting）、边缘光（Rim light）、渐变色叠加、过度的衣褶细节、画面高光泛滥、复杂纹样、复杂链条、过多挂件、过多宝石、过度装饰的武器、信息密度过高、AI 感强的装饰堆砌。
~~~

~~~
生成一张日式幻想 SRPG 风格的重要角色全身立绘。

角色名为伊律德菈·索斯凡纳，女性，外表年龄感约二十五岁，身份为奥瑞利安帝国现任女王，身高 162cm，体型纤细端正，整体气质贤明、聪慧、高贵、威严，带有根植于善良之上的傲慢与自信，身份关键词为女王、贤王、龙使、帝国、守护、繁荣、威严。她拥有垂至膝盖的白色长发，左眼为普通的蓝色眼眸，右眼则如星辰般深蓝，带有白色竖瞳，唇边有两颗尖尖的虎牙。她既有王者的威仪，也带着历经岁月后沉淀出的温柔与坚定。

穿着具有王权象征的中世纪轻幻想女王礼装，主色调为白色、深蓝色、金色，并可融入少量象征龙使身份的深星蓝点缀。材质包含高级布料、丝绸、细腻皮革与精致金属，服装结构可以包含长披风、立领、修身长裙、肩甲或礼仪性腰饰，配有少量帝国纹章、王室装饰与龙使象征细节。手持一把王者佩剑，或一柄兼具礼仪与战斗感的单手长剑。整体设计围绕三个核心视觉记忆点展开：白色长发与异色双眼、女王礼装与帝国王权轮廓、深蓝龙瞳与龙使气息所形成的高贵威严感。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角。姿势为自然站立，身体姿态端庄稳重，可以一手持剑拄地，另一手自然垂放或轻按于身前，展现一位贤王在风雨之后仍立于王座前的姿态。表情平静、自信、威严、聪慧，眼神中带有掌控全局的冷静，也带有对国家与人民的责任感。角色轮廓清晰，剪影鲜明，王者身份、龙使特征与重要角色气场都能一眼辨认，整体具有主控角色级别的存在感与史诗感。

画风统一为：日式幻想 SRPG / JRPG 角色官方设定图（Official Art）风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚。严格使用柔和赛璐璐平涂（Cel-shading, Flat color），平光照明（Flat lighting），阴影边缘清晰，不使用复杂渐变和厚重光影。整体色彩为低饱和自然柔和配色，轻微淡彩质感，画面清爽干净，适合游戏角色立绘与 UI 展示。

服装设计为中世纪轻幻想王权风格，布料、皮革、金属材质区分明确，结构华贵而克制，层级分明。请优先强化角色的大轮廓、主色块、王权身份符号与专属记忆点，使服装结构、色彩分区、佩剑轮廓与装饰重点形成更强的人物个性。整体应体现她作为贤王与龙使的精致度、独特性与角色魅力，同时保持适合游戏角色立绘与 UI 展示的整洁统一感。
~~~

